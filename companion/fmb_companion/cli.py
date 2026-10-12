"""Explicit CLI with fixed JSON status/errors and allowlisted local diagnostics.

Input: CLI arguments; output: counts/status, never argument echoes or tracebacks.
Diagnostics use readable text or --json without constructing the network client.
No daemon install/start, game input, live enrollment or sync on import.
Debug --debug prints sanitized unchanged watch results; README explains codes.
"""

import argparse
import json
import sys
from pathlib import Path

from .browser_export import write_browser_export
from .client import Companion
from .diagnostics import human_report, parse_diagnostics
from .errors import CompanionError
from .export import parse_saved_variables
from .storage import read_stable


class SafeParser(argparse.ArgumentParser):
    def error(self, _message):
        # argparse's default error echoes unknown arguments, possibly secrets.
        raise CompanionError("CLI_ARGUMENTS")


def parser():
    result = SafeParser(
        description="FMB Community Companion — freiwillig und selbst gemeldet, nicht serververifiziert."
    )
    result.add_argument(
        "--debug",
        action="store_true",
        help="Auch unveränderte anonyme Watch-Ergebnisse zeigen.",
    )
    commands = result.add_subparsers(dest="command", required=True)
    enroll = commands.add_parser("enroll", help="Explizit anmelden und privaten Token speichern.")
    enroll.add_argument("--endpoint", required=True)
    enroll.add_argument("--name", required=True)
    enroll.add_argument("--realm", required=True)
    enroll.add_argument("--saved-variables", required=True)
    enroll.add_argument(
        "--consent",
        action="store_true",
        help="Öffentlichen Namen/Realm und freiwillige Ereignisübertragung bestätigen.",
    )
    inspect = commands.add_parser("inspect", help="Export lokal prüfen; keine Netzwerkzugriffe.")
    inspect.add_argument("--saved-variables", required=True)
    diagnostics = commands.add_parser(
        "diagnostics", help="Gespeicherte Diagnose lokal lesen; kein Upload oder Livezugriff."
    )
    diagnostics.add_argument("--saved-variables", required=True)
    diagnostics.add_argument(
        "--json", action="store_true", help="Nur geprüfte Diagnosefelder als JSON ausgeben."
    )
    export = commands.add_parser(
        "export", help="Nur Ranking-JSON für die Website erzeugen; kein Netzwerk."
    )
    export.add_argument("--saved-variables", required=True)
    export.add_argument(
        "--output", required=True, help="Neue .json-Datei; vorhandene Dateien bleiben erhalten."
    )
    for name in ("sync", "watch", "leave"):
        command = commands.add_parser(name)
        if name == "watch":
            command.add_argument(
                "--interval",
                type=float,
                default=10,
                help="Mindestens 10 Sekunden; Strg+C beendet.",
            )
    default_config = str(
        Path.home() / "Library/Application Support/Feberdin/ForeverRanking/participant.json"
    )
    for command in commands.choices.values():
        if command not in (inspect, export, diagnostics):
            command.add_argument(
                "--config",
                default=default_config,
                help="Private JSON-Datei außerhalb WoW; pro Charakter eine eigene Datei.",
            )
    return result


def show(value, stream=None):
    keys = {
        "status",
        "trust",
        "accepted",
        "duplicates",
        "quarantined",
        "expired",
        "enabled",
        "events",
        "code",
        "hint",
    }
    print(
        json.dumps(
            {key: item for key, item in value.items() if key in keys},
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        file=stream or sys.stdout,
    )


def hint(code):
    if code.startswith("DIAGNOSTICS_"):
        return "Gespeicherte Diagnose mit aktuellem Addon nach eigenem Reload/Logout erneut lesen; keine SavedVariables bearbeiten oder Rohdaten veröffentlichen."
    if code.startswith("CONFIG_"):
        return (
            "README: private Token-Datei und Verzeichnisrechte prüfen; Datei nicht in WoW ablegen."
        )
    if code.startswith("OUTPUT_"):
        return "Neue .json-Zieldatei in einem bestehenden beschreibbaren Ordner wählen; vorhandene Datei nicht überschreiben."
    if code.startswith(("EXPORT_", "SOURCE_")):
        return "SavedVariables-Pfad prüfen; nach eigenem Reload/Logout erneut versuchen. WoW-Dateien nicht bearbeiten."
    if code in ("CLOCK_SKEW", "CLOCK_INVALID"):
        return "Systemzeit prüfen; zukünftige Ereignisse werden nicht hochgeladen."
    if code == "CONSENT_REQUIRED":
        return "Erst nach eigener Entscheidung mit --consent anmelden."
    if code == "CLI_ARGUMENTS":
        return "Mit --help die Befehle und notwendigen Parameter anzeigen."
    return "README-Fehlercodes prüfen; keine Token, Namen oder Rohdaten in Logs weitergeben."


def main(argv=None):
    try:
        args = parser().parse_args(argv)
        if args.command == "diagnostics":
            report = parse_diagnostics(read_stable(args.saved_variables))
            if args.json:
                print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
            else:
                print(human_report(report))
            return 0
        if args.command == "export":
            show(write_browser_export(args.saved_variables, args.output))
            return 0
        if args.command == "inspect":
            value = parse_saved_variables(read_stable(args.saved_variables))
            show(
                {
                    "status": "EXPORT_VALID",
                    "enabled": value["enabled"],
                    "events": len(value["events"]),
                    "trust": "self_reported",
                }
            )
            return 0
        app = Companion()
        if args.command == "enroll":
            result = app.enroll(
                args.endpoint,
                args.name,
                args.realm,
                args.saved_variables,
                args.config,
                args.consent,
            )
        elif args.command == "sync":
            result = app.sync(args.config)
        elif args.command == "leave":
            result = app.leave(args.config)
        else:
            previous = None

            def report(value):
                nonlocal previous
                if value != previous or args.debug:
                    show(value)
                    previous = dict(value)

            app.watch(args.config, interval=args.interval, report=report)
            return 0
        show(result)
        return 0
    except CompanionError as error:
        show(
            {"status": "ERROR", "code": error.code, "hint": hint(error.code)},
            sys.stderr,
        )
        return 2
    except KeyboardInterrupt:
        show({"status": "STOPPED"})
        return 0
    except Exception:  # noqa: BLE001 - final CLI privacy boundary reports INTERNAL_ERROR.
        # The CLI is the final boundary. Native failures may contain full
        # paths, response fragments or credentials; no raw traceback is printed.
        show(
            {
                "status": "ERROR",
                "code": "INTERNAL_ERROR",
                "hint": "Lokale Tests ausführen; Fehler mit diesem Code ohne private Rohdaten melden.",
            },
            sys.stderr,
        )
        return 1
