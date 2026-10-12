"""Synthetic cross-language contract: Lua addon export -> companion -> SQLite API.

Input: real Stats/RankingExport modules, invented post-correlation cast GUIDs and
an explicit test opt-in. Output: aggregate assertions through real loopback HTTP.
Invariants: only temporary files/identities; never inspect real SavedVariables,
contact external hosts, log tokens, or execute the companion's Lua input.
Debug: python3 -m unittest discover -s tests -p 'test_ranking_end_to_end.py' -v.
Set LUA_BIN explicitly to test another available interpreter; default is Lua 5.1.
"""

from __future__ import annotations

import http.client
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "companion"))
from fmb_companion.client import Companion
from fmb_companion.errors import CompanionError
from fmb_companion.export import parse_saved_variables
from fmb_companion.storage import load_config

# Use a unique module name: unrelated test suites may already import "server".
spec = importlib.util.spec_from_file_location(
    "fmb_ranking_service_e2e", ROOT / "service/server.py"
)
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)
NOW = 1791763200

LUA_SCENARIO = r"""
local addon, stamp, mode = arg[1], tonumber(arg[2]), arg[3]
issecretvalue = function() return false end
canaccesstable = function() return true end
GetServerTime = function() return stamp end
local ns = {db = {}, Log = function() end}
for _, file in ipairs({"Hash.lua", "CounterCodec.lua", "Stats.lua"}) do
    assert(loadfile(addon .. "/" .. file))("ForeverMouseoverBuff", ns)
end
assert(loadfile(addon .. "/RankingExport.lua"))("ForeverMouseoverBuff", ns)
assert(ns.RankingExport.Initialize())
assert(ns.db.rankingEnabled == false)
assert(ns.RankingExport.SetEnabled(true))
-- This test starts at the confirmed cast boundary. The separate Whisper tests
-- prove SENT/SUCCEEDED correlation and target/class/self-cast exclusion.
for index, id in ipairs({19740,19834,19742,20217}) do
    assert(ns.Stats.Record(id, "Cast-Synthetic-" .. index))
    assert(ns.RankingExport.Record(id))
end
assert(not ns.Stats.Record(19740, "Cast-Synthetic-1"))
assert(ns.Stats.Total() == 4)
assert(ns.db.buffStats.schema == 2)
assert(ns.db.buffStats.spells == nil)
assert(type(ns.db.buffStats.payload) == "string")
assert(#ns.db.buffStats.digest == 64)
if mode == "off" then assert(ns.RankingExport.SetEnabled(false)) end
-- Serialize actual addon-owned state in the ordinary SavedVariables grammar.
-- The companion must parse this as data; it must never execute the Lua file.
local function literal(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    assert(type(value) == "table")
    local rows = {}
    for key, item in pairs(value) do rows[#rows + 1] = "[" .. literal(key) .. "]=" .. literal(item) end
    return "{" .. table.concat(rows, ",") .. "}"
end
io.write("ForeverMouseoverBuffDB = ", literal(ns.db), "\n")
io.write("ForeverMouseoverBuffRankingExport = ", string.format("%q", ForeverMouseoverBuffRankingExport), "\n")
"""


class RankingEndToEndTests(unittest.TestCase):
    """Exercise the published integration rather than replacing either HTTP end."""

    def test_real_lua_export_sync_replay_categories_optout_and_delete(self):
        candidate = os.environ.get("LUA_BIN")
        if candidate:
            lua = (
                shutil.which(candidate)
                if not Path(candidate).is_absolute()
                else candidate
            )
        else:
            lua = ROOT.parent / "Feberdin-HealBot-Forever/runtime/lua-5.1.5/src/lua"
        self.assertTrue(
            lua and Path(lua).is_file(),
            "Lua runtime unavailable; set LUA_BIN explicitly.",
        )

        with tempfile.TemporaryDirectory(prefix="fmb-ranking-e2e-") as directory:
            temporary = Path(directory).resolve()
            source_dir = temporary / "game-fixture"
            source_dir.mkdir()
            source = source_dir / "ForeverMouseoverBuff.lua"
            config = temporary / "private" / "participant.json"
            scenario = temporary / "fixture.lua"
            scenario.write_text(LUA_SCENARIO)

            def saved_variables(mode):
                process = subprocess.run(
                    [
                        str(lua),
                        str(scenario),
                        str(ROOT / "src/ForeverMouseoverBuff"),
                        str(NOW),
                        mode,
                    ],
                    capture_output=True,
                    timeout=10,
                    check=False,
                )
                # The fixture contains no identities/tokens. Keep even unexpected
                # stderr out of assertions; run the Lua fixture directly to debug.
                self.assertEqual(
                    process.returncode, 0, "Synthetic Lua scenario failed."
                )
                self.assertTrue(process.stdout.startswith(b"ForeverMouseoverBuffDB = "))
                return process.stdout

            source.write_bytes(saved_variables("on"))
            original = source.read_bytes()
            decoded = parse_saved_variables(original)
            self.assertTrue(decoded["enabled"])
            self.assertEqual(len(decoded["events"]), 4)
            self.assertEqual(
                {event["spellId"] for event in decoded["events"]},
                {19740, 19834, 19742, 20217},
            )

            server = service.RankingServer(
                ("127.0.0.1", 0), temporary / "ranking.sqlite3", clock=lambda: NOW
            )
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            port = server.server_address[1]
            endpoint = f"http://127.0.0.1:{port}"
            app = Companion(clock=lambda: NOW)

            def ranking(query="group=players"):
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                try:
                    connection.request("GET", "/v1/leaderboard?" + query)
                    response = connection.getresponse()
                    body = response.read()
                    self.assertEqual(response.status, 200)
                    return json.loads(body)
                finally:
                    connection.close()

            try:
                with self.assertRaises(CompanionError) as denied:
                    app.enroll(
                        endpoint, "Syntheticpaladin", "Testrealm", source, config
                    )
                self.assertEqual(denied.exception.code, "CONSENT_REQUIRED")
                self.assertEqual(ranking()["total"], 0)
                self.assertFalse(config.exists())

                enrollment = app.enroll(
                    endpoint,
                    "Syntheticpaladin",
                    "Testrealm",
                    source,
                    config,
                    consent=True,
                )
                self.assertEqual(
                    enrollment, {"status": "ENROLLED", "trust": "self_reported"}
                )
                credentials = load_config(config)
                first = app.sync(config)
                self.assertEqual(
                    (first["accepted"], first["duplicates"], first["quarantined"]),
                    (4, 0, 0),
                )
                replay = app.sync(config)
                self.assertEqual(
                    (replay["accepted"], replay["duplicates"], replay["quarantined"]),
                    (0, 4, 0),
                )
                self.assertEqual(
                    source.read_bytes(),
                    original,
                    "Companion must leave the game file unchanged.",
                )

                players = ranking()
                self.assertEqual(players["trust"], "self_reported")
                self.assertEqual(players["total"], 4)
                self.assertEqual(
                    [
                        (row["displayName"], row["rank"], row["count"])
                        for row in players["rows"]
                    ],
                    [("Syntheticpaladin", 1, 4)],
                )
                self.assertEqual(
                    ranking("group=classes")["rows"][0]["casterClass"], "PALADIN"
                )
                self.assertEqual(
                    {
                        row["buff"]: row["count"]
                        for row in ranking("group=buffs")["rows"]
                    },
                    {"might": 2, "wisdom": 1, "kings": 1},
                )
                self.assertEqual(ranking("group=players&buff=wisdom")["total"], 1)

                source.write_bytes(saved_variables("off"))
                disabled = app.sync(config)
                self.assertEqual(disabled["status"], "EXPORT_DISABLED")
                self.assertEqual(disabled["accepted"], 0)
                self.assertEqual(
                    ranking()["total"],
                    4,
                    "Local opt-out does not silently erase uploaded records.",
                )
                self.assertEqual(
                    app.leave(config), {"status": "LEFT", "trust": "self_reported"}
                )
                self.assertFalse(config.exists())
                self.assertEqual(ranking()["rows"], [])
                self.assertEqual(ranking("group=buffs")["total"], 0)
                with self.assertRaises(CompanionError) as stale:
                    app.transport.request(
                        "POST",
                        endpoint,
                        "/v1/events",
                        {"events": decoded["events"]},
                        credentials["token"],
                    )
                self.assertEqual(stale.exception.code, "AUTH_REQUIRED")
                with server.store.lock:
                    self.assertEqual(
                        server.store.db.execute(
                            "SELECT COUNT(*) FROM participants"
                        ).fetchone()[0],
                        0,
                    )
                    self.assertEqual(
                        server.store.db.execute(
                            "SELECT COUNT(*) FROM events"
                        ).fetchone()[0],
                        0,
                    )
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
                server.store.close()


if __name__ == "__main__":
    unittest.main()
