"""Decode one JSON export from a bounded Lua SavedVariables literal document.

Input: bytes, at most 8 MiB. Output: validated detached JSON contract.
Never evaluate Lua/Python, import player files, follow expressions or log data.
Debug via fixed EXPORT_* codes; tests include string/comment decoys and hostile Lua.
"""

import json
import re

from .errors import CompanionError

FILE_LIMIT = 8 * 1024 * 1024
EXPORT_LIMIT = 1024 * 1024
SPELL_IDS = frozenset(
    (
        19740,
        19834,
        19835,
        19836,
        19837,
        19838,
        25291,
        27140,
        48931,
        48932,
        19742,
        19850,
        19852,
        19853,
        19854,
        25290,
        27142,
        48935,
        48936,
        20217,
    )
)
GLOBAL = b"ForeverMouseoverBuffRankingExport"
IDENT = re.compile(rb"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(
    rb"-?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)"
)
LONG = re.compile(rb"\[(=*)\[")
EVENT_ID = re.compile(r"[A-Za-z0-9_-]{8,96}\Z")


def strict_json(data, code="EXPORT_SCHEMA"):
    """JSON objects cannot hide a duplicate key or nonfinite numeric constant."""

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise CompanionError(code)
            result[key] = value
        return result

    def constant(_):
        raise CompanionError(code)

    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, UnicodeError, RecursionError):
        raise CompanionError(code) from None


class LiteralReader:
    """Small lexer/parser for assignment/literal tables, not a Lua interpreter.

    Unknown globals are parsed without building tables. This establishes context
    before accepting the exact top-level export and rejects executable syntax.
    """

    def __init__(self, data):
        self.data, self.pos, self.buffer, self.tokens = data, 0, [], 0

    def fail(self):
        raise CompanionError("EXPORT_SYNTAX")

    def long_string(self):
        match = LONG.match(self.data, self.pos)
        if not match:
            return False
        end_marker = b"]" + match[1] + b"]"
        end = self.data.find(end_marker, match.end())
        if end < 0:
            self.fail()
        self.pos = end + len(end_marker)
        return True

    def quoted(self):
        quote = self.data[self.pos]
        self.pos += 1
        result = bytearray()
        escapes = {
            97: 7,
            98: 8,
            102: 12,
            110: 10,
            114: 13,
            116: 9,
            118: 11,
            92: 92,
            34: 34,
            39: 39,
        }
        while self.pos < len(self.data):
            value = self.data[self.pos]
            self.pos += 1
            if value == quote:
                return bytes(result)
            if value in (10, 13):
                self.fail()
            if value != 92:
                result.append(value)
                continue
            if self.pos >= len(self.data):
                self.fail()
            value = self.data[self.pos]
            self.pos += 1
            if value in escapes:
                result.append(escapes[value])
            elif 48 <= value <= 57:
                digits = bytes((value,))
                for _ in range(2):
                    if self.pos < len(self.data) and 48 <= self.data[self.pos] <= 57:
                        digits += bytes((self.data[self.pos],))
                        self.pos += 1
                    else:
                        break
                number = int(digits)
                if number > 255:
                    self.fail()
                result.append(number)
            elif value in (10, 13):
                if value == 13 and self.data[self.pos : self.pos + 1] == b"\n":
                    self.pos += 1
                result.append(10)
            else:
                self.fail()
        self.fail()

    def next_token(self):
        while self.pos < len(self.data):
            if self.data[self.pos] in b" \t\r\n\v\f":
                self.pos += 1
            elif self.data[self.pos : self.pos + 2] == b"--":
                self.pos += 2
                if not self.long_string():
                    end = self.data.find(b"\n", self.pos)
                    self.pos = len(self.data) if end < 0 else end + 1
            else:
                break
        self.tokens += 1
        if self.tokens > 250000:
            self.fail()
        if self.pos >= len(self.data):
            return "EOF", None
        char = self.data[self.pos]
        if char in (34, 39):
            return "STRING", self.quoted()
        if char == 91 and self.long_string():
            return "LONG", None
        for pattern, kind in ((IDENT, "IDENT"), (NUMBER, "NUMBER")):
            match = pattern.match(self.data, self.pos)
            if match:
                self.pos = match.end()
                return kind, match[0]
        if char in b"{}[]=,;":
            self.pos += 1
            return chr(char), None
        self.fail()

    def peek(self, offset=0):
        while len(self.buffer) <= offset:
            self.buffer.append(self.next_token())
        return self.buffer[offset]

    def take(self, kind=None):
        token = self.peek()
        if kind is not None and token[0] != kind:
            self.fail()
        del self.buffer[0]
        return token

    def literal(self, depth=0):
        if depth > 64:
            self.fail()
        kind, value = self.peek()
        if kind in ("STRING", "LONG", "NUMBER") or (
            kind == "IDENT" and value in (b"nil", b"true", b"false")
        ):
            return self.take()
        self.take("{")
        while self.peek()[0] != "}":
            if self.peek()[0] == "[":
                self.take()
                self.literal(depth + 1)
                self.take("]")
                self.take("=")
                self.literal(depth + 1)
            elif self.peek()[0] == "IDENT" and self.peek(1)[0] == "=":
                self.take()
                self.take()
                self.literal(depth + 1)
            else:
                self.literal(depth + 1)
            if self.peek()[0] in (",", ";"):
                self.take()
            elif self.peek()[0] != "}":
                self.fail()
        self.take("}")
        return "TABLE", None


def parse_saved_variables(data):
    if not isinstance(data, bytes):
        raise CompanionError("EXPORT_SYNTAX")
    if len(data) > FILE_LIMIT:
        raise CompanionError("SOURCE_TOO_LARGE")
    reader = LiteralReader(data.removeprefix(b"\xef\xbb\xbf"))
    found = None
    while reader.peek()[0] != "EOF":
        name = reader.take("IDENT")[1]
        reader.take("=")
        kind, value = reader.literal()
        if name == GLOBAL:
            if found is not None or kind != "STRING":
                reader.fail()
            if len(value) > EXPORT_LIMIT:
                raise CompanionError("EXPORT_TOO_LARGE")
            found = value
        if reader.peek()[0] == ";":
            reader.take()
    if found is None:
        raise CompanionError("EXPORT_MISSING")
    return validate_export(strict_json(found))


def validate_export(value):
    if (
        type(value) is not dict
        or set(value) != {"schema", "enabled", "casterClass", "events"}
        or type(value["schema"]) is not int
        or value["schema"] != 1
        or type(value["enabled"]) is not bool
        or value["casterClass"] != "PALADIN"
        or type(value["events"]) is not list
        or len(value["events"]) > 1000
        or (not value["enabled"] and value["events"])
    ):
        raise CompanionError("EXPORT_SCHEMA")
    seen, events = set(), []
    for event in value["events"]:
        if (
            type(event) is not dict
            or set(event) != {"id", "spellId", "eventTime"}
            or type(event["id"]) is not str
            or not EVENT_ID.fullmatch(event["id"])
            or event["id"] in seen
            or type(event["spellId"]) is not int
            or event["spellId"] not in SPELL_IDS
            or type(event["eventTime"]) is not int
            or not 1 <= event["eventTime"] <= 4102444800
        ):
            raise CompanionError("EXPORT_SCHEMA")
        seen.add(event["id"])
        events.append(dict(event))
    return {
        "schema": 1,
        "enabled": value["enabled"],
        "casterClass": "PALADIN",
        "events": events,
    }
