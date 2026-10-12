"""Read a saved, explicitly selected diagnostic snapshot without executing Lua.

Input: at most 8 MiB of SavedVariables bytes. Output: detached allowlisted data
and a human-readable report; no path, name, GUID, token or raw error is returned.
Invariant: unknown fields are parsed only as literals and never retained. The
existing lexer bounds nesting and token count; selected arrays have strict caps.
Debug: DIAGNOSTICS_* fixed error/warning codes and tests/test_diagnostics.py.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

from .diagnostic_codes import CODES
from .errors import CompanionError
from .export import FILE_LIMIT, LiteralReader

GLOBAL = b"ForeverMouseoverBuffDB"
COUNT_LIMIT = 1_000_000_000
TIME_LIMIT = 4_102_444_800
VERSION = re.compile(rb"[0-9]+\.[0-9]+\.[0-9]+\Z")
BUILD = re.compile(rb"[0-9]{1,12}\Z")
SCALAR = object()
SKIP = object()
FLAGS = (
    "enabled",
    "debug",
    "sound",
    "whisper",
    "receiveWhispers",
    "showOutgoingWhispers",
    "sealSound",
    "rankingEnabled",
    "buttonReady",
    "routerReady",
)
CLIENT_VERSIONS = ("clientVersion", "clientBuild")


@dataclass(frozen=True)
class ArrayShape:
    """Select only positive array positions within a fixed diagnostic limit."""

    limit: int
    item: object


EVENT_FIELDS = {key: SCALAR for key in (b"sequence", b"code", b"severity", b"origin", b"timestamp")}
STATUS_FIELDS = {
    key.encode("ascii"): SCALAR for key in (*FLAGS, *CLIENT_VERSIONS, "clientInterface")
}
DIAGNOSTIC_FIELDS = {
    **{
        key: SCALAR
        for key in (
            b"schema",
            b"version",
            b"sequence",
            b"attempts",
            b"confirmed",
            b"failed",
            b"fallbackReason",
        )
    },
    b"events": ArrayShape(64, EVENT_FIELDS),
    b"codes": ArrayShape(40, SCALAR),
    b"status": STATUS_FIELDS,
}
DATABASE_FIELDS = {b"diagnostics": DIAGNOSTIC_FIELDS}


def integer(node, maximum=COUNT_LIMIT):
    """Accept bounded integral Lua numerals, never booleans or numeric strings."""
    if node is None or node[0] != "NUMBER" or len(node[1]) > 32:
        return None
    raw = node[1]
    try:
        if raw.lower().startswith((b"0x", b"-0x")):
            value = int(raw, 16)
        else:
            value = Decimal(raw.decode("ascii"))
        if 0 <= value <= maximum and value == int(value):
            return int(value)
    except (ValueError, InvalidOperation, OverflowError):
        return None
    return None


class DiagnosticReader(LiteralReader):
    """Reuse the safe lexer, selecting only the diagnostic subtree and keys.

    Other globals, unknown table fields and unknown nested content are consumed
    by LiteralReader.literal, which never constructs or executes their tables.
    Selected scalar tokens remain typed until an exact vocabulary validates them.
    """

    def fail(self):
        raise CompanionError("DIAGNOSTICS_SYNTAX")

    def field_key(self, implicit, depth):
        if self.peek()[0] == "[":
            self.take()
            node = self.literal(depth + 1)
            self.take("]")
            self.take("=")
            if node[0] == "STRING":
                return node[1], implicit
            return integer(node), implicit
        if self.peek()[0] == "IDENT" and self.peek(1)[0] == "=":
            key = self.take()[1]
            self.take("=")
            return key, implicit
        return implicit, implicit + 1

    def project(self, shape, depth=0):
        if depth > 64:
            self.fail()
        if shape is SCALAR or self.peek()[0] != "{":
            return self.literal(depth)
        self.take("{")
        selected, implicit = {}, 1
        while self.peek()[0] != "}":
            key, implicit = self.field_key(implicit, depth)
            if isinstance(shape, ArrayShape):
                if type(key) is int and key > shape.limit:
                    raise CompanionError("DIAGNOSTICS_LIMIT")
                child = shape.item if type(key) is int and key >= 1 else SKIP
            else:
                child = shape.get(key, SKIP)
            if child is SKIP:
                self.literal(depth + 1)
            else:
                if key in selected:
                    self.fail()
                selected[key] = self.project(child, depth + 1)
            if self.peek()[0] in (",", ";"):
                self.take()
            elif self.peek()[0] != "}":
                self.fail()
        self.take("}")
        return "TABLE", selected


def table(node):
    if node is not None and node[0] == "TABLE" and isinstance(node[1], dict):
        return node[1]
    return None


def version(node, *, build=False):
    pattern = BUILD if build else VERSION
    if node is None or node[0] != "STRING" or len(node[1]) > 32 or not pattern.fullmatch(node[1]):
        return None
    return node[1].decode("ascii")


def known_code(node):
    if node is None or node[0] != "STRING" or len(node[1]) > 80:
        return None
    try:
        value = node[1].decode("ascii")
    except UnicodeError:
        return None
    return value if value in CODES else None


def array(node, warnings):
    if node is None:
        return []
    values = table(node)
    if values is None or set(values) != set(range(1, len(values) + 1)):
        warnings.add("DIAGNOSTICS_FIELDS_FILTERED")
        return []
    return [values[index] for index in range(1, len(values) + 1)]


def filtered(warnings):
    warnings.add("DIAGNOSTICS_FIELDS_FILTERED")


def sanitize_status(node, warnings):
    """Only documented booleans and numeric client versions leave the parser."""
    if node is None:
        return {}
    values = table(node)
    if values is None:
        filtered(warnings)
        return {}
    result = {}
    for key in FLAGS:
        value = values.get(key.encode("ascii"))
        if value is None:
            continue
        if value[0] == "IDENT" and value[1] in (b"true", b"false"):
            result[key] = value[1] == b"true"
        else:
            filtered(warnings)
    for key in CLIENT_VERSIONS:
        value = values.get(key.encode("ascii"))
        if value is None:
            continue
        clean = version(value, build=key == "clientBuild")
        if clean is None:
            filtered(warnings)
        else:
            result[key] = clean
    value = values.get(b"clientInterface")
    if value is not None:
        clean = integer(value, 1_000_000)
        if clean is None or clean == 0:
            filtered(warnings)
        else:
            result["clientInterface"] = clean
    return result


def sanitize_events(node, sequence, warnings):
    """Keep ordered known events; canonical catalog supplies level and origin."""
    result, previous = [], 0
    for item in array(node, warnings):
        values = table(item)
        if values is None:
            filtered(warnings)
            continue
        number = integer(values.get(b"sequence"))
        code = known_code(values.get(b"code"))
        if number is None or not previous < number <= sequence or code is None:
            filtered(warnings)
            continue
        severity, origin = CODES[code]
        # Caller-controlled severity/origin cannot relabel a known error as INFO.
        for field, expected in ((b"severity", severity), (b"origin", origin)):
            if values.get(field) != ("STRING", expected.encode("ascii")):
                filtered(warnings)
        event = {"sequence": number, "code": code, "severity": severity, "origin": origin}
        if b"timestamp" in values:
            stamp = integer(values[b"timestamp"], TIME_LIMIT)
            if stamp is None or stamp == 0:
                filtered(warnings)
            else:
                event["timestamp"] = stamp
        result.append(event)
        previous = number
    return result


def sanitize_diagnostics(node):
    """Return a minimal report; unknown/invalid values never enter its text."""
    values = table(node)
    if values is None:
        raise CompanionError("DIAGNOSTICS_SCHEMA")
    schema_node = values.get(b"schema")
    legacy = schema_node is None or schema_node == ("IDENT", b"nil")
    if not legacy and integer(schema_node) != 2:
        raise CompanionError("DIAGNOSTICS_SCHEMA")
    warnings = {"DIAGNOSTICS_LEGACY"} if legacy else set()
    result = {
        "status": "DIAGNOSTICS_OK",
        "scope": "saved_snapshot",
        "format": "legacy" if legacy else "schema2",
        "schema": None if legacy else 2,
        "counts": {},
        "codes": [],
        "events": [],
        "snapshot": {},
    }
    if b"version" in values:
        clean = version(values[b"version"])
        if clean is None:
            filtered(warnings)
        else:
            result["version"] = clean
    for key in ("attempts", "confirmed", "failed"):
        if key.encode("ascii") in values:
            clean = integer(values[key.encode("ascii")])
            if clean is None:
                filtered(warnings)
            else:
                result["counts"][key] = clean
    for node in array(values.get(b"codes"), warnings):
        code = known_code(node)
        if code is None:
            filtered(warnings)
        else:
            result["codes"].append(code)
    if b"fallbackReason" in values:
        code = known_code(values[b"fallbackReason"])
        if code is None:
            filtered(warnings)
        else:
            result["fallbackReason"] = code
    if not legacy:
        sequence = integer(values.get(b"sequence"))
        if sequence is None:
            filtered(warnings)
        else:
            result["sequence"] = sequence
            result["events"] = sanitize_events(values.get(b"events"), sequence, warnings)
        result["snapshot"] = sanitize_status(values.get(b"status"), warnings)
    if not result["codes"] and not result["events"]:
        warnings.add("DIAGNOSTICS_NO_EVENTS")
    result["warnings"] = sorted(warnings)
    return result


def parse_diagnostics(data):
    """Find one real top-level DB assignment, never text/comment/string decoys."""
    if not isinstance(data, bytes):
        raise CompanionError("DIAGNOSTICS_SYNTAX")
    if len(data) > FILE_LIMIT:
        raise CompanionError("SOURCE_TOO_LARGE")
    reader = DiagnosticReader(data.removeprefix(b"\xef\xbb\xbf"))
    found, seen = None, False
    while reader.peek()[0] != "EOF":
        name = reader.take("IDENT")[1]
        reader.take("=")
        if name == GLOBAL:
            if seen:
                raise CompanionError("DIAGNOSTICS_SYNTAX")
            seen = True
            database = table(reader.project(DATABASE_FIELDS))
            if database is not None:
                found = database.get(b"diagnostics")
        else:
            reader.literal()
        if reader.peek()[0] == ";":
            reader.take()
    if found is None:
        raise CompanionError("DIAGNOSTICS_MISSING")
    return sanitize_diagnostics(found)


def human_report(report):
    """Render only a sanitized report; never include input paths or raw values."""
    lines = [
        "Forever Mouseover Buff – gespeicherte Diagnose",
        "Lokale Datei, Stand des letzten Speicherns. Kein Livezugriff und kein Upload.",
        "Version: " + report.get("version", "nicht gespeichert"),
        "Format: "
        + (
            "Altformat, ohne strukturierte Ereignisse"
            if report["format"] == "legacy"
            else "Schema 2"
        ),
    ]
    for key, label in (
        ("attempts", "Buff-Versuche"),
        ("confirmed", "Bestätigte Zauberereignisse"),
        ("failed", "Fehlgeschlagen"),
    ):
        lines.append(label + ": " + str(report["counts"].get(key, "nicht gespeichert")))
    if report.get("fallbackReason"):
        lines.append("Fallback: " + report["fallbackReason"])
    for key, value in report["snapshot"].items():
        text = ("an" if value else "aus") if type(value) is bool else str(value)
        lines.append("Status " + key + ": " + text)
    if report["events"]:
        lines.append("Letzte Ereignisse:")
        for event in report["events"]:
            stamp = "Zeit nicht gespeichert"
            if "timestamp" in event:
                stamp = datetime.fromtimestamp(event["timestamp"], timezone.utc).strftime(
                    "%Y-%m-%d %H:%M:%S UTC"
                )
            lines.append(
                f"  #{event['sequence']} {stamp} | {event['severity']} | {event['origin']} | {event['code']}"
            )
    elif report["codes"]:
        lines.append("Letzte Diagnosecodes: " + ", ".join(report["codes"]))
    else:
        lines.append("Keine gespeicherten Diagnoseereignisse verfügbar.")
    for warning in report["warnings"]:
        if warning == "DIAGNOSTICS_FIELDS_FILTERED":
            lines.append("Hinweis: Unbekannte oder ungültige Diagnosewerte wurden ausgeblendet.")
        elif warning == "DIAGNOSTICS_LEGACY":
            lines.append(
                "Hinweis: Altformat gelesen; strukturierte Daten entstehen mit dem aktuellen Addon nach eigenem Reload/Logout."
            )
    return "\n".join(lines)
