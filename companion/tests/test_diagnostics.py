"""Synthetic read-only diagnostic CLI tests, never real WoW files or credentials.

Input: temporary Lua literal fixtures; output: deterministic unittest results.
Invariant: no Lua execution, upload, private data output or input modification.
Debug: python3 -m unittest discover -s companion/tests -p test_diagnostics.py -v.
"""

import contextlib
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fmb_companion.cli import main
from fmb_companion.diagnostic_codes import CODES
from fmb_companion.diagnostics import parse_diagnostics
from fmb_companion.errors import CompanionError
from fmb_companion.export import FILE_LIMIT


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.source = Path(self.temporary.name).resolve() / "Synthetic.lua"

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self, contents, *, json_output=True):
        self.source.write_bytes(contents)
        before = self.source.read_bytes()
        out, err = io.StringIO(), io.StringIO()
        arguments = ["diagnostics", "--saved-variables", str(self.source)]
        if json_output:
            arguments.append("--json")
        with (
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
            patch("fmb_companion.cli.Companion", side_effect=AssertionError("network forbidden")),
        ):
            status = main(arguments)
        self.assertEqual(
            self.source.read_bytes(), before, "diagnostic reader must never write WoW data"
        )
        return status, out.getvalue(), err.getvalue()

    def test_legacy_diagnostics_can_be_read_locally_without_ranking_export_or_network(self):
        status, output, error = self.invoke(
            b'ForeverMouseoverBuffDB = { diagnostics = {version="0.7.1", '
            b'codes={"STATS_RECORDED"}, attempts=2, confirmed=1, failed=0} }'
        )
        self.assertEqual(
            status, 0, "diagnostics command must read the existing local diagnostic record"
        )
        self.assertEqual(error, "")
        result = json.loads(output)
        self.assertEqual(result["status"], "DIAGNOSTICS_OK")
        self.assertEqual(result["format"], "legacy")
        self.assertIsNone(result["schema"])
        self.assertEqual(result["version"], "0.7.1")
        self.assertEqual(result["codes"], ["STATS_RECORDED"])
        self.assertEqual(result["counts"], {"attempts": 2, "confirmed": 1, "failed": 0})
        self.assertIn("DIAGNOSTICS_LEGACY", result["warnings"])

    def report(self, fields, *, json_output=True):
        return self.invoke(
            b"ForeverMouseoverBuffDB={diagnostics={" + fields + b"}}",
            json_output=json_output,
        )

    def assert_error(self, data, expected):
        status, output, error = self.invoke(data)
        self.assertEqual(status, 2)
        self.assertEqual(output, "")
        self.assertEqual(json.loads(error)["code"], expected)
        self.assertNotIn(str(self.source), error)
        self.assertNotIn("PRIVATE_CANARY", error)

    def test_schema2_json_shows_bounded_public_status_and_chronological_events(self):
        status, output, error = self.report(
            b'schema=2,version="0.7.2",sequence=12,attempts=4,confirmed=3,failed=1,'
            b'fallbackReason="STATS_RECORDED",codes={"STATS_RECORDED"},'
            b'events={{sequence=11,code="STATS_RECORDED",severity="INFO",'
            b'origin="STATS",timestamp=1791763200},{sequence=12,'
            b'code="STATS_RECORDED",severity="INFO",origin="STATS"}},'
            b"status={enabled=true,debug=false,sound=true,whisper=false,"
            b"receiveWhispers=true,showOutgoingWhispers=false,sealSound=true,"
            b"rankingEnabled=false,buttonReady=true,routerReady=false,"
            b'clientVersion="12.0.1",clientBuild="12345",clientInterface=120001}'
        )
        self.assertEqual((status, error), (0, ""))
        result = json.loads(output)
        self.assertEqual(result["format"], "schema2")
        self.assertEqual(result["schema"], 2)
        self.assertEqual(result["sequence"], 12)
        self.assertEqual(result["warnings"], [])
        self.assertEqual(result["counts"], {"attempts": 4, "confirmed": 3, "failed": 1})
        self.assertEqual(result["fallbackReason"], "STATS_RECORDED")
        self.assertEqual([event["sequence"] for event in result["events"]], [11, 12])
        self.assertEqual(result["events"][0]["timestamp"], 1791763200)
        self.assertNotIn("timestamp", result["events"][1])
        self.assertEqual(result["snapshot"]["clientInterface"], 120001)
        self.assertIs(result["snapshot"]["buttonReady"], True)
        self.assertIs(result["snapshot"]["rankingEnabled"], False)

    def test_human_output_explains_saved_snapshot_and_renders_only_catalog_values(self):
        status, output, error = self.report(
            b'schema=2,version="0.7.2",sequence=1,attempts=1,'
            b'events={{sequence=1,code="STATS_RECORDED",severity="INFO",'
            b'origin="STATS",timestamp=1}},status={enabled=true}',
            json_output=False,
        )
        self.assertEqual((status, error), (0, ""))
        self.assertIn("Kein Livezugriff und kein Upload", output)
        self.assertIn("Version: 0.7.2", output)
        self.assertIn("Buff-Versuche: 1", output)
        self.assertIn("Status enabled: an", output)
        self.assertIn("1970-01-01 00:00:01 UTC | INFO | STATS | STATS_RECORDED", output)
        self.assertIn("Bestätigte Zauberereignisse: nicht gespeichert", output)

    def test_private_unknown_fields_codes_versions_and_mislabelled_event_data_are_filtered(self):
        data = (
            b'OtherGlobal={token="PRIVATE_CANARY",name="PRIVATE_CANARY"};'
            b'ForeverMouseoverBuffRankingExport="PRIVATE_CANARY";'
            b'ForeverMouseoverBuffDB={stats={name="PRIVATE_CANARY"},diagnostics={'
            b'schema=2,version="PRIVATE_CANARY",sequence=2,attempts="PRIVATE_CANARY",'
            b'name="PRIVATE_CANARY",guid="PRIVATE_CANARY",token="PRIVATE_CANARY",'
            b'codes={"STATS_PRIVATE_CANARY","STATS_RECORDED","PRIVATE_CANARY"},'
            b'fallbackReason="PRIVATE_CANARY",status={enabled=true,key="PRIVATE_CANARY",'
            b'clientVersion="12.0.1 PRIVATE_CANARY",clientBuild="PRIVATE_CANARY",'
            b'clientInterface="PRIVATE_CANARY",sound="PRIVATE_CANARY"},'
            b'events={{sequence=1,code="STATS_PRIVATE_CANARY",origin="PRIVATE_CANARY"},'
            b'{sequence=2,code="STATS_RECORDED",severity="PRIVATE_CANARY",'
            b'origin="PRIVATE_CANARY",message="PRIVATE_CANARY",timestamp="PRIVATE_CANARY"}}}}'
        )
        for json_output in (True, False):
            with self.subTest(json_output=json_output):
                status, output, error = self.invoke(data, json_output=json_output)
                self.assertEqual((status, error), (0, ""))
                self.assertNotIn("PRIVATE_CANARY", output)
                self.assertNotIn(str(self.source), output)
                if json_output:
                    result = json.loads(output)
                    self.assertEqual(result["snapshot"], {"enabled": True})
                    self.assertEqual(result["codes"], ["STATS_RECORDED"])
                    self.assertEqual(result["counts"], {})
                    self.assertNotIn("version", result)
                    self.assertNotIn("fallbackReason", result)
                    self.assertEqual(
                        result["events"],
                        [
                            {
                                "sequence": 2,
                                "code": "STATS_RECORDED",
                                "severity": "INFO",
                                "origin": "STATS",
                            }
                        ],
                    )
                    self.assertIn("DIAGNOSTICS_FIELDS_FILTERED", result["warnings"])

    def test_exact_python_code_catalog_matches_lua_logger_contract(self):
        path = Path(__file__).resolve().parents[2] / "src/ForeverMouseoverBuff/Diagnostics.lua"
        source = path.read_text()
        entries = re.findall(
            r'\["([A-Z0-9_]+)"\] = \{severity = "([A-Z]+)", origin = "([A-Z_]+)"\}',
            source,
        )
        self.assertGreater(len(entries), 0)
        self.assertEqual(len(entries), len({code for code, _, _ in entries}))
        self.assertEqual(CODES, {code: (level, origin) for code, level, origin in entries})

    def test_quoted_escaped_keys_comments_bom_and_decoys_do_not_change_assignment_selection(self):
        data = (
            b"\xef\xbb\xbf-- ForeverMouseoverBuffDB={diagnostics={schema=99}}\n"
            b'Other="ForeverMouseoverBuffDB={diagnostics={schema=99}}";'
            b"Long=[==[ForeverMouseoverBuffDB={diagnostics={schema=99}}]==];"
            b"Nested={ForeverMouseoverBuffDB={diagnostics={schema=99}}};"
            b'ForeverMouseoverBuffDB={["diagnos\\116ics"]={["schema"]=2,'
            b'["sequence"]=1,["codes"]={[0x1]="STATS_RECORDED"}}}'
        )
        status, output, error = self.invoke(data)
        self.assertEqual((status, error), (0, ""))
        self.assertEqual(json.loads(output)["codes"], ["STATS_RECORDED"])

    def test_duplicate_selected_keys_or_database_assignment_are_rejected(self):
        for data in (
            b"ForeverMouseoverBuffDB={} ForeverMouseoverBuffDB={}",
            b"ForeverMouseoverBuffDB={diagnostics={},diagnostics={}}",
            b"ForeverMouseoverBuffDB={diagnostics={schema=2,schema=2}}",
            b'ForeverMouseoverBuffDB={diagnostics={codes={"STATS_RECORDED",[1]="STATS_RECORDED"}}}',
        ):
            with self.subTest(data=data):
                self.assert_error(data, "DIAGNOSTICS_SYNTAX")

    def test_executable_lua_and_malformed_literal_documents_are_rejected_without_execution(self):
        for data in (
            b'ForeverMouseoverBuffDB=(function() error("PRIVATE_CANARY") end)()',
            b"ForeverMouseoverBuffDB={diagnostics={attempts=1+1}}",
            b'ForeverMouseoverBuffDB={diagnostics={}}; os.execute("PRIVATE_CANARY")',
            b'ForeverMouseoverBuffDB={diagnostics={version="PRIVATE_CANARY}}',
            b"ForeverMouseoverBuffDB={diagnostics={attempts=NaN}}",
            b"ForeverMouseoverBuffDB.diagnostics={}",
        ):
            with self.subTest(data=data):
                self.assert_error(data, "DIAGNOSTICS_SYNTAX")

    def test_size_depth_and_token_limits_apply_even_to_unknown_fields(self):
        self.assert_error(b" " * (FILE_LIMIT + 1), "SOURCE_TOO_LARGE")
        self.assert_error(b"Other=" + b"{" * 66 + b"}" * 66, "DIAGNOSTICS_SYNTAX")
        self.assert_error(b"Other={" + b"0," * 125001 + b"}", "DIAGNOSTICS_SYNTAX")

    def test_diagnostic_array_caps_are_enforced(self):
        event = b'{sequence=%d,code="STATS_RECORDED",severity="INFO",origin="STATS"}'
        for count, valid in ((64, True), (65, False)):
            fields = (
                b"schema=2,sequence=100,events={"
                + b",".join(event % number for number in range(1, count + 1))
                + b"}"
            )
            status, output, error = self.report(fields)
            if valid:
                self.assertEqual((status, error), (0, ""))
                self.assertEqual(len(json.loads(output)["events"]), count)
            else:
                self.assertEqual(status, 2)
                self.assertEqual(json.loads(error)["code"], "DIAGNOSTICS_LIMIT")
        for count, valid in ((40, True), (41, False)):
            status, output, error = self.report(
                b"codes={" + b",".join([b'"STATS_RECORDED"'] * count) + b"}"
            )
            if valid:
                self.assertEqual((status, error), (0, ""))
                self.assertEqual(len(json.loads(output)["codes"]), count)
            else:
                self.assertEqual(status, 2)
                self.assertEqual(json.loads(error)["code"], "DIAGNOSTICS_LIMIT")

    def test_array_holes_are_not_reindexed_or_claimed_as_valid_history(self):
        status, output, error = self.report(b'codes={[2]="STATS_RECORDED"}')
        self.assertEqual((status, error), (0, ""))
        result = json.loads(output)
        self.assertEqual(result["codes"], [])
        self.assertIn("DIAGNOSTICS_FIELDS_FILTERED", result["warnings"])

    def test_invalid_or_future_schema_and_missing_diagnostics_have_fixed_errors(self):
        for data, code in (
            (b"ForeverMouseoverBuffDB={}", "DIAGNOSTICS_MISSING"),
            (b"Other={diagnostics={}}", "DIAGNOSTICS_MISSING"),
            (b'ForeverMouseoverBuffDB={diagnostics="PRIVATE_CANARY"}', "DIAGNOSTICS_SCHEMA"),
            (b"ForeverMouseoverBuffDB={diagnostics={schema=3}}", "DIAGNOSTICS_SCHEMA"),
            (b'ForeverMouseoverBuffDB={diagnostics={schema="2"}}', "DIAGNOSTICS_SCHEMA"),
        ):
            with self.subTest(code=code, data=data):
                self.assert_error(data, code)

    def test_bad_counts_are_absent_instead_of_reported_as_zero(self):
        for value in (b"-1", b"1.5", b"1000000001", b"1e99999999", b"true", b'"42"', b"{}"):
            with self.subTest(value=value):
                status, output, error = self.report(b"attempts=" + value)
                self.assertEqual((status, error), (0, ""))
                result = json.loads(output)
                self.assertNotIn("attempts", result["counts"])
                self.assertIn("DIAGNOSTICS_FIELDS_FILTERED", result["warnings"])

    def test_integral_hex_and_decimal_numerals_are_accepted_within_bounds(self):
        status, output, error = self.report(b"attempts=0xff,confirmed=1e3,failed=1000000000")
        self.assertEqual((status, error), (0, ""))
        self.assertEqual(
            json.loads(output)["counts"],
            {"attempts": 255, "confirmed": 1000, "failed": 1_000_000_000},
        )

    def test_client_version_build_and_interface_use_the_lua_logger_bounds(self):
        status, output, error = self.report(
            b'schema=2,sequence=0,status={clientVersion="12.0.1234567",'
            b'clientBuild="123456789012",clientInterface=1000000}'
        )
        self.assertEqual((status, error), (0, ""))
        self.assertEqual(
            json.loads(output)["snapshot"],
            {
                "clientVersion": "12.0.1234567",
                "clientBuild": "123456789012",
                "clientInterface": 1000000,
            },
        )
        status, output, error = self.report(
            b'schema=2,sequence=0,status={clientVersion="12.0",'
            b'clientBuild="123.4",clientInterface=1000001}'
        )
        self.assertEqual((status, error), (0, ""))
        self.assertEqual(json.loads(output)["snapshot"], {})

    def test_event_sequence_must_be_increasing_and_not_exceed_snapshot(self):
        events = b",".join(
            b'{sequence=%d,code="STATS_RECORDED",severity="INFO",origin="STATS"}' % number
            for number in (0, 2, 1, 3, 5, 4)
        )
        status, output, error = self.report(b"schema=2,sequence=4,events={" + events + b"}")
        self.assertEqual((status, error), (0, ""))
        result = json.loads(output)
        self.assertEqual([item["sequence"] for item in result["events"]], [2, 3, 4])
        self.assertIn("DIAGNOSTICS_FIELDS_FILTERED", result["warnings"])

    def test_legacy_empty_diagnostics_are_readable_without_inventing_events(self):
        status, output, error = self.report(b"", json_output=False)
        self.assertEqual((status, error), (0, ""))
        self.assertIn("Altformat", output)
        self.assertIn("Keine gespeicherten Diagnoseereignisse", output)
        self.assertIn("nicht gespeichert", output)

    def test_symlink_and_missing_path_are_rejected_without_echoing_paths(self):
        self.source.symlink_to(Path(self.temporary.name).resolve() / "PRIVATE_CANARY")
        for expected in ("PATH_SYMLINK", "SOURCE_UNAVAILABLE"):
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                status = main(["diagnostics", "--saved-variables", str(self.source)])
            self.assertEqual(status, 2)
            self.assertEqual(json.loads(err.getvalue())["code"], expected)
            self.assertEqual(out.getvalue(), "")
            self.assertNotIn("PRIVATE_CANARY", err.getvalue())
            self.assertNotIn(str(self.source), err.getvalue())
            if self.source.is_symlink():
                self.source.unlink()

    def test_cli_rejects_upload_or_config_arguments_without_echoing_values(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = main(
                [
                    "diagnostics",
                    "--saved-variables",
                    str(self.source),
                    "--endpoint",
                    "PRIVATE_CANARY",
                    "--consent",
                ]
            )
        self.assertEqual(status, 2)
        self.assertEqual(json.loads(err.getvalue())["code"], "CLI_ARGUMENTS")
        self.assertNotIn("PRIVATE_CANARY", err.getvalue())
        self.assertEqual(out.getvalue(), "")

    def test_parser_rejects_non_bytes_without_coercion_or_raw_details(self):
        with self.assertRaises(CompanionError) as error:
            parse_diagnostics("PRIVATE_CANARY")
        self.assertEqual(error.exception.code, "DIAGNOSTICS_SYNTAX")


if __name__ == "__main__":
    unittest.main()
