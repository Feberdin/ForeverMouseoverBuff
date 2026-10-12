"""Exercise real Lua diagnostic storage through the separate read-only CLI.

Input: invented clocks/settings and a temporary SavedVariables file. Output:
contract assertions; no game access, networking, production files or identities.
Invariant: Lua runs only our fixture/module; the reader treats its result as data.
Debug: LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENARIO = r"""
local ns, db = {}, { privateCanary = "SYNTHETIC_PRIVATE_DO_NOT_PRINT" }
issecretvalue = function() return false end
canaccesstable = function(value) return type(value) == "table" end
local clock = 10
GetTime = function() return clock end
GetServerTime = function() return 1791763200 + clock end
assert(loadfile(arg[1] .. "/Diagnostics.lua"))("ForeverMouseoverBuff", ns)
local log = ns.DiagnosticLog
assert(log.Initialize(db, "0.7.2"))
log.UpdateStatus({enabled=true, rankingEnabled=false, whisper=true,
    clientVersion="1.60.1", clientBuild="12345", clientInterface=16001,
    unknown="SYNTHETIC_PRIVATE_DO_NOT_PRINT"})
log.Increment("attempts")
log.Record("CAST_REQUESTED")
clock = clock + 3
log.Increment("confirmed")
log.Record("CAST_CONFIRMED")
clock = clock + 3
log.Record("STATS_INTEGRITY_FAILED")
local function literal(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    assert(type(value) == "table")
    local rows = {}
    for key, item in pairs(value) do
        rows[#rows+1] = "[" .. literal(key) .. "]=" .. literal(item)
    end
    return "{" .. table.concat(rows, ",") .. "}"
end
io.write("ForeverMouseoverBuffDB = ", literal(db), "\n")
"""


class DiagnosticsEndToEndTests(unittest.TestCase):
    def test_lua_saved_state_roundtrips_through_local_cli_without_private_fields(self):
        candidate = os.environ.get("LUA_BIN")
        lua = (
            shutil.which(candidate)
            if candidate
            else str(ROOT.parent / "Feberdin-HealBot-Forever/runtime/lua-5.1.5/src/lua")
        )
        self.assertTrue(
            lua and Path(lua).is_file(), "Set LUA_BIN to an available Lua interpreter."
        )
        with tempfile.TemporaryDirectory(prefix="fmb-diag-e2e-") as directory:
            fixture = Path(directory).resolve() / "fixture.lua"
            source = Path(directory).resolve() / "SavedVariables.lua"
            fixture.write_text(SCENARIO)
            execution = subprocess.run(
                [lua, str(fixture), str(ROOT / "src/ForeverMouseoverBuff")],
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(execution.returncode, 0, execution.stderr.decode())
            source.write_bytes(execution.stdout)
            before = source.read_bytes()
            reader = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "companion/companion.py"),
                    "diagnostics",
                    "--saved-variables",
                    str(source),
                    "--json",
                ],
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(reader.returncode, 0, reader.stderr.decode())
            self.assertEqual(reader.stderr, b"")
            self.assertEqual(source.read_bytes(), before)
            self.assertNotIn(b"SYNTHETIC_PRIVATE_DO_NOT_PRINT", reader.stdout)
            report = json.loads(reader.stdout)
            self.assertEqual(report["version"], "0.7.2")
            self.assertEqual(report["schema"], 2)
            self.assertEqual(report["warnings"], [])
            self.assertEqual(
                report["counts"], {"attempts": 1, "confirmed": 1, "failed": 0}
            )
            self.assertEqual(
                report["snapshot"],
                {
                    "enabled": True,
                    "rankingEnabled": False,
                    "whisper": True,
                    "clientVersion": "1.60.1",
                    "clientBuild": "12345",
                    "clientInterface": 16001,
                },
            )
            self.assertEqual(
                [event["code"] for event in report["events"]],
                [
                    "DIAGNOSTIC_STARTED",
                    "CAST_REQUESTED",
                    "CAST_CONFIRMED",
                    "STATS_INTEGRITY_FAILED",
                ],
            )
            self.assertEqual(
                report["events"][-1],
                {
                    "sequence": 4,
                    "code": "STATS_INTEGRITY_FAILED",
                    "severity": "ERROR",
                    "origin": "STATS",
                    "timestamp": 1791763216,
                },
            )


if __name__ == "__main__":
    unittest.main()
