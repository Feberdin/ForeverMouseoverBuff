"""Synthetic parser/disk/HTTP-boundary tests; no real enrollment or uploads.

Run: python3 -m unittest discover -s companion/tests -v from the project root.
Fixtures keep names/tokens synthetic, game source read-only and transport in RAM.
"""

import contextlib
import copy
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from email.message import Message
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fmb_companion.cli import main
from fmb_companion.client import Companion, HTTPTransport, NoRedirect, validate_endpoint
from fmb_companion.errors import CompanionError
from fmb_companion.export import parse_saved_variables, validate_export
from fmb_companion.storage import (
    load_config,
    read_stable,
)

NOW = 1791763200
TOKEN = "t" * 43
PID = "a" * 32


def export_value(enabled=True, count=1):
    return {
        "schema": 1,
        "enabled": enabled,
        "casterClass": "PALADIN",
        "events": [
            {"id": f"{NOW}-{index + 1}", "spellId": 20217, "eventTime": NOW}
            for index in range(count)
        ]
        if enabled
        else [],
    }


def lua_file(value):
    inner = json.dumps(value, separators=(",", ":"))
    literal = inner.replace("\\", "\\\\").replace('"', '\\"')
    return (
        'Other = { ["nested"] = {true, false, nil, -1.2e3, 0x12}, }\n'
        'ForeverMouseoverBuffRankingExport = "' + literal + '"\n'
    ).encode()


class FakeHTTP:
    def __init__(self):
        self.calls = []
        self.failure = None
        self.upload_response = None

    def request(self, method, endpoint, path, body=None, token=None):
        self.calls.append((method, endpoint, path, copy.deepcopy(body), token))
        if self.failure:
            raise CompanionError(self.failure)
        if path == "/v1/participants":
            return 201, {"participantId": PID, "token": TOKEN, "trust": "self_reported"}
        if method == "DELETE":
            return 200, {"deleted": True, "trust": "self_reported"}
        return 200, self.upload_response or {
            "accepted": len(body["events"]),
            "duplicates": 0,
            "quarantined": 0,
            "trust": "self_reported",
        }


class TestCompanion(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.source = self.root / "input" / "Synthetic.lua"
        self.source.parent.mkdir()
        self.source.write_bytes(lua_file(export_value()))
        self.config = self.root / "private" / "participant.json"
        self.http = FakeHTTP()
        self.app = Companion(self.http, clock=lambda: NOW)

    def tearDown(self):
        self.tmp.cleanup()

    def expect_code(self, code, function, *args, **kwargs):
        with self.assertRaises(CompanionError) as raised:
            function(*args, **kwargs)
        self.assertEqual(raised.exception.code, code)

    def enroll(self):
        self.app.enroll(
            "http://127.0.0.1:18449",
            "Synthetic",
            "Testrealm",
            self.source,
            self.config,
            consent=True,
        )

    def test_parser_accepts_only_the_top_level_export_and_ignores_decoys(self):
        data = (
            b'-- ForeverMouseoverBuffRankingExport = "evil"\n'
            b'--[=[ ForeverMouseoverBuffRankingExport = "evil" ]=]\n'
            b'Decoy = "ForeverMouseoverBuffRankingExport = \\"bad\\""\n'
            b'Long = [=[ForeverMouseoverBuffRankingExport = "evil"]=]\n'
            b'Nested = {ForeverMouseoverBuffRankingExport = "evil"}\n'
        ) + lua_file(export_value())
        self.assertEqual(parse_saved_variables(data), export_value())

    def test_lua_decimal_quote_slash_and_escaped_newline_decode_without_execution(self):
        data = lua_file(export_value()).replace(b'\\"', b"\\034")
        self.assertEqual(parse_saved_variables(data), export_value())
        data = lua_file(export_value()).replace(b'{\\"schema', b'{\\\n\\"schema')
        self.assertEqual(parse_saved_variables(data), export_value())

    def test_duplicate_assignment_expression_and_executable_lua_are_rejected(self):
        for data in (
            lua_file(export_value()) * 2,
            lua_file(export_value()) + b'os.execute("touch should-never-exist")',
            lua_file(export_value())[:-1] + b' .. "suffix"\n',
            b'local ForeverMouseoverBuffRankingExport = "x"',
            b"ForeverMouseoverBuffRankingExport = [=[{}]=]",
        ):
            with self.subTest(data_length=len(data)):
                self.expect_code("EXPORT_SYNTAX", parse_saved_variables, data)

    def test_missing_export_and_truncated_string_are_safe_errors(self):
        self.expect_code("EXPORT_MISSING", parse_saved_variables, b"Other = {}")
        self.expect_code("EXPORT_SYNTAX", parse_saved_variables, lua_file(export_value())[:-3])

    def test_size_and_depth_bounds_prevent_unbounded_parsing(self):
        self.expect_code("SOURCE_TOO_LARGE", parse_saved_variables, b" " * (8 * 1024 * 1024 + 1))
        self.expect_code(
            "EXPORT_TOO_LARGE",
            parse_saved_variables,
            b'ForeverMouseoverBuffRankingExport = "' + b"x" * (1024 * 1024 + 1) + b'"',
        )
        self.expect_code("EXPORT_SYNTAX", parse_saved_variables, b"Other=" + b"{" * 70 + b"}" * 70)

    def test_exact_json_keys_types_spells_times_and_queue_size_are_checked(self):
        bad = []
        for key, value in (
            ("schema", True),
            ("enabled", 1),
            ("casterClass", "MAGE"),
            ("extra", 0),
        ):
            item = export_value()
            item[key] = value
            bad.append(item)
        for key, value in (
            ("id", "bad"),
            ("id", "<script>"),
            ("spellId", 25898),
            ("spellId", True),
            ("eventTime", -1),
            ("eventTime", 1.2),
            ("extra", "x"),
        ):
            item = export_value()
            item["events"][0][key] = value
            bad.append(item)
        bad.extend((export_value(count=1001), {**export_value(), "enabled": False}))
        item = export_value()
        item["events"] *= 2
        bad.append(item)
        for item in bad:
            self.expect_code("EXPORT_SCHEMA", validate_export, item)
        self.assertEqual(validate_export(export_value(False)), export_value(False))

    def test_json_duplicate_keys_and_nonfinite_constants_are_rejected(self):
        for text in ('{"schema":1,"schema":1}', '{"n":NaN}'):
            data = ('ForeverMouseoverBuffRankingExport="' + text.replace('"', '\\"') + '"').encode()
            self.expect_code("EXPORT_SCHEMA", parse_saved_variables, data)

    def test_source_is_read_only_and_symlinks_are_rejected(self):
        before = self.source.read_bytes()
        self.assertEqual(read_stable(self.source), before)
        self.assertEqual(self.source.read_bytes(), before)
        link = self.root / "link.lua"
        link.symlink_to(self.source)
        self.expect_code("PATH_SYMLINK", read_stable, link)

    def test_unstable_stat_snapshot_is_rejected_before_upload(self):
        original = self.source.stat()
        values = list(original)
        values[6] += 1
        modified = os.stat_result(values)
        with patch("fmb_companion.storage.os.fstat", side_effect=[original, modified]):
            self.expect_code("SOURCE_UNSTABLE", read_stable, self.source)

    def test_https_and_loopback_only_no_credentials_query_fragment_or_basepath(self):
        for value in (
            "http://127.0.0.1:18449",
            "http://[::1]:18449",
            "https://example.invalid",
        ):
            self.assertEqual(validate_endpoint(value), value)
        for value in (
            "http://example.invalid",
            "ftp://localhost",
            "https://u:p@example.invalid",
            "https://example.invalid/a",
            "https://example.invalid?x=1",
            "https://example.invalid#x",
        ):
            self.expect_code("ENDPOINT_INVALID", validate_endpoint, value)

    def test_enrollment_requires_explicit_consent_and_does_no_network_without_it(self):
        self.expect_code(
            "CONSENT_REQUIRED",
            self.app.enroll,
            "http://127.0.0.1:18449",
            "Synthetic",
            "Testrealm",
            self.source,
            self.config,
        )
        self.assertEqual(self.http.calls, [])

    def test_enroll_saves_private_config_outside_game_without_printing_or_changing_source(
        self,
    ):
        before = self.source.read_bytes()
        self.enroll()
        self.assertTrue(
            self.config.is_file(), "successful enrollment must save private credentials"
        )
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.config.parent.stat().st_mode), 0o700)
        cfg = load_config(self.config)
        self.assertEqual(cfg["token"], TOKEN)
        self.assertNotIn("displayName", cfg)
        self.assertNotIn("realm", cfg)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(self.http.calls[0][3]["consent"], True)

    def test_config_in_game_source_folder_or_symlink_is_rejected_before_enrollment(
        self,
    ):
        for path in (
            self.source.parent / "token.json",
            self.root / "WTF" / "token.json",
            self.root / "Interface" / "token.json",
            self.root / "WoW" / "token.json",
        ):
            self.expect_code(
                "CONFIG_LOCATION",
                self.app.enroll,
                "http://127.0.0.1:18449",
                "Synthetic",
                "Testrealm",
                self.source,
                path,
                consent=True,
            )
        self.assertEqual(self.http.calls, [])

    def test_existing_or_insecure_config_is_never_silently_replaced(self):
        self.enroll()
        count = len(self.http.calls)
        self.expect_code(
            "CONFIG_EXISTS",
            self.app.enroll,
            "http://127.0.0.1:18449",
            "Synthetic",
            "Testrealm",
            self.source,
            self.config,
            consent=True,
        )
        self.assertEqual(len(self.http.calls), count)
        self.config.chmod(0o644)
        self.expect_code("CONFIG_PERMISSIONS", load_config, self.config)

    def test_sync_obeys_live_export_off_and_sends_batches_of_at_most_100(self):
        self.enroll()
        self.source.write_bytes(lua_file(export_value(count=205)))
        result = self.app.sync(self.config)
        self.assertEqual(result["accepted"], 205)
        uploads = [call for call in self.http.calls if call[2] == "/v1/events"]
        self.assertEqual([len(call[3]["events"]) for call in uploads], [100, 100, 5])
        self.assertTrue(all(call[4] == TOKEN for call in uploads))
        self.source.write_bytes(lua_file(export_value(False)))
        count = len(self.http.calls)
        self.assertEqual(self.app.sync(self.config)["status"], "EXPORT_DISABLED")
        self.assertEqual(len(self.http.calls), count)

    def test_repeat_sync_uses_server_deduplication_without_persisting_event_receipts(
        self,
    ):
        self.enroll()
        self.app.sync(self.config)
        before = self.config.read_bytes()
        self.http.upload_response = {
            "accepted": 0,
            "duplicates": 1,
            "quarantined": 0,
            "trust": "self_reported",
        }
        self.assertEqual(self.app.sync(self.config)["duplicates"], 1)
        self.assertEqual(self.config.read_bytes(), before)

    def test_old_unsent_events_cannot_block_recent_events_but_future_clock_is_an_error(
        self,
    ):
        self.enroll()
        value = export_value(count=2)
        value["events"][0]["eventTime"] = NOW - 604801
        self.source.write_bytes(lua_file(value))
        result = self.app.sync(self.config)
        self.assertEqual(result["expired"], 1)
        self.assertEqual(result["accepted"], 1)
        value["events"][1]["eventTime"] = NOW + 301
        self.source.write_bytes(lua_file(value))
        self.expect_code("CLOCK_SKEW", self.app.sync, self.config)

    def test_bad_upload_response_never_claims_acceptance(self):
        self.enroll()
        self.http.upload_response = {
            "accepted": 99,
            "duplicates": 0,
            "quarantined": 0,
            "trust": "verified",
        }
        self.expect_code("RESPONSE_INVALID", self.app.sync, self.config)

    def test_leave_removes_config_only_after_confirmed_server_deletion(self):
        self.enroll()
        self.http.failure = "AUTH_REQUIRED"
        self.expect_code("AUTH_REQUIRED", self.app.leave, self.config)
        self.assertTrue(self.config.is_file())
        self.http.failure = None
        self.app.leave(self.config)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.http.calls[-1][0], "DELETE")

    def test_watch_enforces_ten_seconds_and_retries_partial_files_without_spinning(
        self,
    ):
        self.expect_code("POLL_INTERVAL", self.app.watch, self.config, interval=9)
        self.enroll()
        sleeps = []
        reports = []
        self.source.write_bytes(b'ForeverMouseoverBuffRankingExport="partial')

        def pause(delay):
            sleeps.append(delay)
            self.source.write_bytes(lua_file(export_value()))

        self.app.watch(
            self.config,
            interval=10,
            sleep=pause,
            stop=lambda: len(reports) >= 2,
            report=reports.append,
        )
        self.assertEqual(sleeps, [10])
        self.assertEqual(reports[0]["status"], "EXPORT_SYNTAX")
        self.assertEqual(reports[1]["accepted"], 1)

    def test_cli_inspect_reports_counts_but_never_synthetic_identities_or_paths(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = main(["inspect", "--saved-variables", str(self.source)])
        self.assertEqual(code, 0)
        self.assertIn("EXPORT_VALID", output.getvalue())
        self.assertIn('"events":1', output.getvalue())
        self.assertNotIn(str(self.source), output.getvalue())
        self.assertNotIn(TOKEN, output.getvalue())

    def test_cli_export_creates_only_ranking_json_without_network_or_source_changes(self):
        destination = self.root / "ranking.json"
        original = self.source.read_bytes()
        output = io.StringIO()
        with patch("fmb_companion.client.HTTPTransport.request") as request:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = main(
                    ["export", "--saved-variables", str(self.source), "--output", str(destination)]
                )
            request.assert_not_called()
        self.assertEqual(code, 0, "Local export command must succeed before any enrollment.")
        self.assertEqual(json.loads(destination.read_text()), export_value())
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertIn("EXPORT_WRITTEN", output.getvalue())
        self.assertNotIn(str(destination), output.getvalue())

    def test_cli_export_refuses_existing_output_symlink_or_executable_input(self):
        destination = self.root / "ranking.json"
        destination.write_text("existing")
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(
                main(
                    ["export", "--saved-variables", str(self.source), "--output", str(destination)]
                ),
                2,
            )
        self.assertEqual(destination.read_text(), "existing")
        self.assertIn("OUTPUT_EXISTS", output.getvalue())
        link = self.root / "link.json"
        link.symlink_to(destination)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(
                main(["export", "--saved-variables", str(self.source), "--output", str(link)]), 2
            )
        self.source.write_bytes(b'os.execute("do not run")')
        fresh = self.root / "fresh.json"
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(
                main(["export", "--saved-variables", str(self.source), "--output", str(fresh)]), 2
            )
        self.assertFalse(fresh.exists())

    def test_cli_errors_do_not_echo_user_arguments_or_exception_data(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = main(["unknown-private-value"])
        self.assertEqual(code, 2)
        self.assertIn("CLI_ARGUMENTS", output.getvalue())
        self.assertNotIn("unknown-private-value", output.getvalue())

    def test_failed_config_write_compensates_enrollment_without_exposing_token(self):
        with patch(
            "fmb_companion.client.save_config",
            side_effect=CompanionError("CONFIG_WRITE_FAILED"),
        ):
            self.expect_code("ENROLL_SAVE_FAILED_ROLLED_BACK", self.enroll)
        self.assertFalse(self.config.exists())
        self.assertEqual([call[0] for call in self.http.calls], ["POST", "DELETE"])

    def test_transport_sets_json_length_bearer_and_disables_redirects_and_proxies(self):
        class Response:
            status = 200
            headers = Message()
            headers["Content-Type"] = "application/json"

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, maximum):
                return b'{"accepted":1,"duplicates":0,"quarantined":0,"trust":"self_reported"}'

        with patch("fmb_companion.client.urllib.request.build_opener") as factory:
            factory.return_value.open.return_value = Response()
            status, body = HTTPTransport().request(
                "POST",
                "http://127.0.0.1:18449",
                "/v1/events",
                {"events": export_value()["events"]},
                TOKEN,
            )
            self.assertEqual(status, 200)
            self.assertEqual(body["accepted"], 1)
            request = factory.return_value.open.call_args.args[0]
            self.assertEqual(request.get_header("Authorization"), "Bearer " + TOKEN)
            self.assertEqual(request.get_header("Content-length"), str(len(request.data)))
            self.assertEqual(factory.call_args.args[0].proxies, {})
            self.assertIsInstance(factory.call_args.args[1], NoRedirect)
        self.expect_code(
            "ENDPOINT_REDIRECT",
            NoRedirect().redirect_request,
            None,
            None,
            302,
            None,
            None,
            "https://other.invalid",
        )


if __name__ == "__main__":
    unittest.main()
