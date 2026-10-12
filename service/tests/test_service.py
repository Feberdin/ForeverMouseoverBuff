"""Synthetic HTTP acceptance tests for the community ranking boundary.

Input: localhost requests with invented identities and clocks. Output: unittest results.
Invariants: no real player accounts, external network, credentials or game process.
Debug: python3 -m unittest discover -s tests -v, from service/.
"""

import http.client
import json
import sqlite3
import tempfile
import threading
import unittest
from contextlib import closing
from pathlib import Path

from server import RankingServer

NOW = 1_791_756_000


class ServiceTests(unittest.TestCase):
    """Exercise real HTTP parsing, SQLite transactions and leaderboard queries."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.db_path = Path(self.directory.name) / "ranking.sqlite3"
        self.clock = [NOW]
        self.server = RankingServer(
            ("127.0.0.1", 0), self.db_path, clock=lambda: self.clock[0]
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        if hasattr(self.server, "store"):
            self.server.store.close()
        self.directory.cleanup()

    def request(self, method, path, data=None, token=None, headers=None, raw=None):
        request_headers = {"Content-Type": "application/json"}
        if token:
            request_headers["Authorization"] = "Bearer " + token
        request_headers.update(headers or {})
        body = (
            raw
            if raw is not None
            else (json.dumps(data).encode() if data is not None else None)
        )
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        result = response.read()
        response_headers = dict(response.getheaders())
        status = response.status
        connection.close()
        if "application/json" in response_headers.get("Content-Type", ""):
            result = json.loads(result)
        return status, result, response_headers

    def participant(self, name="Testpaladin", realm="Testrealm"):
        status, result, _ = self.request(
            "POST",
            "/v1/participants",
            {
                "displayName": name,
                "realm": realm,
                "casterClass": "PALADIN",
                "consent": True,
            },
        )
        self.assertEqual(status, 201, result)
        return result

    def event(self, number=1, spell=19740, timestamp=NOW):
        return {
            "id": "synthetic-event-" + str(number),
            "spellId": spell,
            "eventTime": timestamp,
        }

    def upload(self, participant, events, **extra):
        return self.request(
            "POST", "/v1/events", {"events": events, **extra}, participant["token"]
        )

    def leaderboard(self, query="group=players"):
        status, result, _ = self.request("GET", "/v1/leaderboard?" + query)
        self.assertEqual(status, 200, result)
        return result

    def test_enrollment_requires_explicit_consent_and_stores_only_token_hash(self):
        participant = self.participant()
        self.assertEqual(participant["trust"], "self_reported")
        self.assertGreaterEqual(len(participant["token"]), 40)
        for consent in (False, None, 1, "true"):
            status, error, _ = self.request(
                "POST",
                "/v1/participants",
                {
                    "displayName": "Other",
                    "realm": "Testrealm",
                    "casterClass": "PALADIN",
                    "consent": consent,
                },
            )
            self.assertEqual(status, 400, error)
            self.assertEqual(error["error"], "CONSENT_REQUIRED")
        with closing(sqlite3.connect(self.db_path)) as connection:
            dump = "\n".join(connection.iterdump())
        self.assertNotIn(participant["token"], dump)
        self.assertIn("self_reported", dump)

    def test_confirmed_local_events_create_player_class_and_buff_rankings(self):
        first = self.participant("Testpaladin")
        second = self.participant("Otherpaladin")
        status, result, _ = self.upload(
            first, [self.event(1), self.event(2, 19834), self.event(3, 19742)]
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["accepted"], 3)
        self.assertEqual(result["duplicates"], 0)
        self.assertEqual(result["trust"], "self_reported")
        self.assertEqual(self.upload(second, [self.event(1, 20217)])[0], 200)
        players = self.leaderboard()
        self.assertEqual(players["total"], 4)
        self.assertEqual(
            [
                (row["rank"], row["displayName"], row["count"])
                for row in players["rows"]
            ],
            [(1, "Testpaladin", 3), (2, "Otherpaladin", 1)],
        )
        self.assertTrue(all(row["trust"] == "self_reported" for row in players["rows"]))
        classes = self.leaderboard("group=classes")
        self.assertEqual(
            [(row["casterClass"], row["count"]) for row in classes["rows"]],
            [("PALADIN", 4)],
        )
        buffs = self.leaderboard("group=buffs")
        self.assertEqual(
            {row["buff"]: row["count"] for row in buffs["rows"]},
            {"might": 2, "wisdom": 1, "kings": 1},
        )
        filtered = self.leaderboard("group=players&class=PALADIN&buff=wisdom&limit=1")
        self.assertEqual(filtered["total"], 1)
        self.assertEqual(filtered["rows"][0]["displayName"], "Testpaladin")
        self.assertNotIn("token", json.dumps(players))

    def test_million_count_and_unknown_metadata_are_rejected_without_inserting(self):
        participant = self.participant()
        for bad in (
            {"count": 1000000},
            {"total": 1000000},
            {"trust": "verified"},
            {"rank": 1},
        ):
            status, result, _ = self.upload(participant, [self.event()], **bad)
            self.assertEqual(status, 400, result)
        for bad in (
            {"count": 1000000},
            {"recipient": "Someone"},
            {"casterClass": "MAGE"},
        ):
            event = {**self.event(), **bad}
            self.assertEqual(self.upload(participant, [event])[0], 400)
        self.assertEqual(self.leaderboard()["total"], 0)

    def test_duplicate_ids_are_idempotent_durable_and_conflicting_payload_rolls_back(
        self,
    ):
        participant = self.participant()
        event = self.event()
        self.assertEqual(self.upload(participant, [event])[1]["accepted"], 1)
        self.assertEqual(self.upload(participant, [event, event])[1]["duplicates"], 2)
        conflict = {**event, "spellId": 19742}
        status, result, _ = self.upload(participant, [self.event(2), conflict])
        self.assertEqual(status, 409, result)
        self.assertEqual(self.leaderboard()["total"], 1)
        self.server.store.close()
        from server import Store

        self.server.store = Store(self.db_path, clock=lambda: self.clock[0])
        self.assertEqual(self.upload(participant, [event])[1]["duplicates"], 1)
        self.clock[0] += 8 * 86400
        self.assertEqual(self.upload(participant, [event])[1]["duplicates"], 1)

    def test_invalid_spell_times_ids_and_class_are_rejected(self):
        participant = self.participant()
        invalid = [
            self.event(spell=999999),
            self.event(timestamp=NOW + 301),
            self.event(timestamp=NOW - 7 * 86400 - 1),
            self.event(timestamp=True),
            self.event(timestamp=1.5),
            {**self.event(), "id": "x';DROP TABLE events;--"},
            {**self.event(), "id": "x"},
            {**self.event(), "spellId": True},
        ]
        for event in invalid:
            self.assertEqual(self.upload(participant, [event])[0], 400, event)
        status, _, _ = self.request(
            "POST",
            "/v1/participants",
            {
                "displayName": "Mage",
                "realm": "Testrealm",
                "casterClass": "MAGE",
                "consent": True,
            },
        )
        self.assertEqual(status, 400)
        self.assertEqual(
            self.upload(participant, [self.event(timestamp=NOW - 7 * 86400)])[0], 200
        )

    def test_suspicious_bursts_are_quarantined_and_not_ranked(self):
        participant = self.participant()
        events = [self.event(number) for number in range(1, 63)]
        status, result, _ = self.upload(participant, events)
        self.assertEqual(status, 200, result)
        self.assertEqual((result["accepted"], result["quarantined"]), (60, 2))
        self.assertEqual(self.leaderboard()["total"], 60)
        self.assertEqual(self.upload(participant, [events[-1]])[1]["duplicates"], 1)
        with closing(sqlite3.connect(self.db_path)) as connection:
            reasons = connection.execute(
                "SELECT reason FROM events WHERE status = 'quarantined'"
            ).fetchall()
        self.assertEqual(reasons, [("MINUTE_LIMIT",), ("MINUTE_LIMIT",)])

    def test_daily_limit_quarantines_and_out_of_order_import_is_sorted(self):
        self.server.store.day_limit = 2
        participant = self.participant()
        status, result, _ = self.upload(
            participant,
            [
                self.event(3, timestamp=NOW - 120),
                self.event(1, timestamp=NOW - 360),
                self.event(2, timestamp=NOW - 240),
            ],
        )
        self.assertEqual(status, 200, result)
        self.assertEqual((result["accepted"], result["quarantined"]), (2, 1))
        with closing(sqlite3.connect(self.db_path)) as connection:
            quarantined = connection.execute(
                "SELECT event_id, reason FROM events WHERE status='quarantined'"
            ).fetchall()
        self.assertEqual(quarantined, [("synthetic-event-3", "DAY_LIMIT")])

    def test_authentication_deletion_and_identity_collision_are_explicit(self):
        participant = self.participant()
        self.assertEqual(
            self.request("POST", "/v1/events", {"events": [self.event()]})[0], 401
        )
        self.assertEqual(
            self.request("POST", "/v1/events", {"events": [self.event()]}, "invalid")[
                0
            ],
            401,
        )
        self.upload(participant, [self.event()])
        status, _, _ = self.request(
            "POST",
            "/v1/participants",
            {
                "displayName": "TESTPALADIN",
                "realm": "testrealm",
                "casterClass": "PALADIN",
                "consent": True,
            },
        )
        self.assertEqual(status, 409)
        self.assertEqual(
            self.request("DELETE", "/v1/participant", token=participant["token"])[0],
            200,
        )
        self.assertEqual(self.leaderboard()["rows"], [])
        self.assertEqual(
            self.request("DELETE", "/v1/participant", token=participant["token"])[0],
            401,
        )
        with closing(sqlite3.connect(self.db_path)) as connection:
            self.assertEqual(
                connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], 0
            )
            self.assertEqual(
                connection.execute("SELECT COUNT(*) FROM participants").fetchone()[0], 0
            )

    def test_enrollment_rate_limit_and_upload_batch_boundaries(self):
        for number in range(8):
            self.participant("Synthetic" + chr(65 + number))
        self.assertEqual(
            self.request(
                "POST",
                "/v1/participants",
                {
                    "displayName": "More",
                    "realm": "Testrealm",
                    "casterClass": "PALADIN",
                    "consent": True,
                },
            )[0],
            429,
        )
        self.clock[0] += 3601
        participant = self.participant("Afterhour")
        for events in ([], [self.event(i) for i in range(101)], "events"):
            self.assertEqual(self.upload(participant, events)[0], 400)

    def test_http_parser_rejects_ambiguous_unsafe_and_cross_origin_input(self):
        cases = [
            (b'{"consent":true,"consent":false}', {}),
            (b"[]", {}),
            (b'{"x":NaN}', {}),
            (b"not json", {}),
            (b"{}", {"Content-Type": "text/plain"}),
            (b"{}", {"Origin": "https://unrelated.invalid"}),
            (b"{}", {"Host": "unrelated.invalid"}),
            (b"{}", {"Transfer-Encoding": "chunked"}),
        ]
        for body, headers in cases:
            status, _, _ = self.request(
                "POST", "/v1/participants", raw=body, headers=headers
            )
            self.assertIn(status, (400, 403, 415), headers)
        status, _, _ = self.request("POST", "/v1/participants", raw=b" " * 40000)
        self.assertEqual(status, 413)
        for name in (
            "<script>alert(1)</script>",
            "Name\nAnother",
            "Bad|cffff00",
            "X\u200bY",
        ):
            self.assertEqual(
                self.request(
                    "POST",
                    "/v1/participants",
                    {
                        "displayName": name,
                        "realm": "Testrealm",
                        "casterClass": "PALADIN",
                        "consent": True,
                    },
                )[0],
                400,
            )

    def test_dashboard_and_limits_are_explicit_and_untrusted_text_uses_textcontent(
        self,
    ):
        status, html, headers = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"Community", html)
        self.assertIn(b"nicht serverbest", html)
        self.assertIn("Content-Security-Policy", headers)
        status, script, _ = self.request("GET", "/app.js")
        self.assertEqual(status, 200)
        self.assertIn(b"textContent", script)
        self.assertNotIn(b"innerHTML", script)
        for query in (
            "group=bad",
            "limit=0",
            "limit=101",
            "limit=1&limit=2",
            "class=MAGE",
            "buff=evil",
            "private=yes",
        ):
            self.assertEqual(
                self.request("GET", "/v1/leaderboard?" + query)[0], 400, query
            )
        self.assertEqual(self.request("GET", "/../../server.py")[0], 404)
        self.assertEqual(self.request("GET", "/health")[1]["trust"], "self_reported")

    def test_invalid_unicode_scalars_and_excessively_large_numbers_are_client_errors(
        self,
    ):
        payload = {
            "displayName": "Name\ud800",
            "realm": "Testrealm",
            "casterClass": "PALADIN",
            "consent": True,
        }
        self.assertEqual(self.request("POST", "/v1/participants", payload)[0], 400)
        raw = b'{"count":' + b"9" * 5000 + b"}"
        self.assertEqual(self.request("POST", "/v1/participants", raw=raw)[0], 400)

    def test_logs_contain_neither_identity_authorization_nor_request_payload(self):
        with self.assertLogs("fmb.ranking", level="DEBUG") as captured:
            participant = self.participant("Privateexample")
            self.upload(participant, [self.event()])
            self.request(
                "POST", "/v1/events", {"events": []}, "private-secret-placeholder"
            )
        text = "\n".join(captured.output)
        for hidden in (
            "Privateexample",
            "Testrealm",
            participant["token"],
            "private-secret-placeholder",
            "127.0.0.1",
        ):
            self.assertNotIn(hidden, text)
        self.assertIn("EVENT_BATCH", text)

    def test_local_upload_page_offers_preview_consent_and_own_identity_lookup(self):
        status, html, _ = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b'id="ranking-file"', html)
        self.assertIn(b'id="upload-consent"', html)
        self.assertIn(b'id="upload-send"', html)
        participant = self.participant()
        self.assertEqual(self.request("GET", "/v1/participant")[0], 401)
        status, profile, _ = self.request(
            "GET", "/v1/participant", token=participant["token"]
        )
        self.assertEqual(status, 200)
        self.assertEqual(
            profile,
            {
                "participantId": participant["participantId"],
                "displayName": "Testpaladin",
                "realm": "Testrealm",
                "casterClass": "PALADIN",
                "trust": "self_reported",
            },
        )
        self.assertNotIn("token", json.dumps(profile))
        for path in ("/upload-core.js", "/upload.js"):
            self.assertEqual(self.request("GET", path)[0], 200)

    def test_equal_scores_share_rank_and_spell_ranks_roll_into_families(self):
        first = self.participant("First")
        second = self.participant("Second")
        self.upload(first, [self.event(1, 19740)])
        self.upload(second, [self.event(1, 48932)])
        rows = self.leaderboard()["rows"]
        self.assertEqual([row["rank"] for row in rows], [1, 1])
        buffs = self.leaderboard("group=buffs")["rows"]
        self.assertEqual([(row["buff"], row["count"]) for row in buffs], [("might", 2)])


if __name__ == "__main__":
    unittest.main()
