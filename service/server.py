"""A local, explicitly unverified community buff ranking without third-party code.

Input: opted-in participant registration and bounded, individually identified buff
claims over HTTP. Output: SQLite records and aggregate JSON/HTML rankings. Never
accept totals, identities of buff recipients, or client assertions of verification.
Debug: --debug logs fixed operation/error codes, never headers, names or tokens.
Run: python3 server.py --db ./data/ranking.sqlite3 (127.0.0.1:18449 by default).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import secrets
import sqlite3
import threading
import time
import unicodedata
import uuid
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

VERSION = "0.2.0"
TRUST = "self_reported"
MAX_BODY_BYTES = 32768
MAX_BATCH = 100
EVENT_ID = re.compile(r"[A-Za-z0-9_-]{8,96}\Z")
LOG = logging.getLogger("fmb.ranking")
STATIC = Path(__file__).with_name("static")
BUFFS = {
    "might": (
        "Segen der Macht",
        (19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 48931, 48932),
    ),
    "wisdom": (
        "Segen der Weisheit",
        (19742, 19850, 19852, 19853, 19854, 25290, 27142, 48935, 48936),
    ),
    "kings": ("Segen der Könige", (20217,)),
}
SPELLS = {spell: buff for buff, (_, spells) in BUFFS.items() for spell in spells}


class ServiceError(Exception):
    """Only fixed, reviewed messages may cross the HTTP/log boundary."""

    def __init__(self, status, code, message):
        super().__init__(code)
        self.status = status
        self.code = code
        self.message = message


def invalid(code, message):
    raise ServiceError(400, code, message)


def exact_fields(value, required):
    if not isinstance(value, dict) or set(value) != set(required):
        invalid(
            "INVALID_FIELDS", "Die Felder passen nicht zum API-Vertrag. OpenAPI prüfen."
        )


def public_name(value, *, realm=False):
    """Accept visible character/realm names, never control codes or HTML markup."""
    if not isinstance(value, str):
        invalid("INVALID_NAME", "Charaktername und Realm müssen sichtbarer Text sein.")
    normalized = unicodedata.normalize("NFC", value)
    allowed = " '-_" if realm else " '-"
    try:
        name_bytes = len(normalized.encode("utf-8"))
    except UnicodeError:
        invalid("INVALID_NAME", "Name/Realm muss gültigen Unicode-Text enthalten.")
    if (
        normalized != normalized.strip()
        or not 2 <= len(normalized) <= 64
        or name_bytes > 96
        or not all(
            char.isalpha() or char in allowed or (realm and char.isdigit())
            for char in normalized
        )
        or not any(char.isalpha() for char in normalized)
    ):
        invalid(
            "INVALID_NAME",
            "Name/Realm: 2–64 sichtbare Zeichen, höchstens 96 UTF-8-Bytes.",
        )
    return normalized


class RateLimiter:
    """Bound memory and registration/upload frequency, not proof of real gameplay.

    Peer identifiers are keyed hashes kept in RAM for one hour. They are never
    written to the database/log. A reverse proxy must additionally limit requests.
    """

    def __init__(self, clock):
        self.clock = clock
        self.key = secrets.token_bytes(32)
        self.items = {}
        self.lock = threading.Lock()

    def check(self, scope, identity, limit, window):
        now = self.clock()
        digest = hashlib.blake2b(
            identity.encode(), key=self.key, digest_size=16
        ).digest()
        bucket = (scope, digest)
        with self.lock:
            for previous in list(self.items):
                times = self.items[previous]
                while times and (times[0] <= now - 3600 or times[0] > now):
                    times.popleft()
                if not times:
                    del self.items[previous]
            if bucket not in self.items and len(self.items) >= 4096:
                raise ServiceError(
                    429, "RATE_CAPACITY", "Zu viele Anfragen. Später erneut versuchen."
                )
            times = self.items.setdefault(bucket, deque())
            if sum(stamp > now - window for stamp in times) >= limit:
                raise ServiceError(
                    429, "RATE_LIMIT", "Anfragelimit erreicht. Später erneut versuchen."
                )
            times.append(now)


class Store:
    """Serialize small SQLite transactions; calculate every count on the server.

    Only event IDs deduplicate. A changed ID payload rejects the entire batch.
    The event clock is a client claim. observed_time records the actual receipt.
    Quarantine excludes suspicious events without pretending they were verified.
    """

    minute_limit = 60
    day_limit = 10000

    def __init__(self, path, *, clock=time.time):
        path = Path(path)
        if path.is_symlink() or not path.parent.is_dir():
            raise ValueError(
                "DB_PATH_INVALID: Datenbank-Elternordner muss existieren; keine Symlinks."
            )
        self.clock = clock
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False, timeout=5)
        os.chmod(path, 0o600)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        if self.db.execute("PRAGMA user_version").fetchone()[0] not in (0, 1):
            self.db.close()
            raise ValueError(
                "DB_VERSION_UNSUPPORTED: Datenbankversion passt nicht zu diesem Dienst."
            )
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS participants (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                realm TEXT NOT NULL,
                identity_key TEXT NOT NULL UNIQUE,
                caster_class TEXT NOT NULL CHECK(caster_class='PALADIN'),
                token_hash TEXT NOT NULL UNIQUE,
                consent_time INTEGER NOT NULL,
                trust TEXT NOT NULL CHECK(trust='self_reported')
            );
            CREATE TABLE IF NOT EXISTS events (
                participant_id TEXT NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
                event_id TEXT NOT NULL,
                spell_id INTEGER NOT NULL,
                buff TEXT NOT NULL,
                event_time INTEGER NOT NULL,
                observed_time INTEGER NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('accepted','quarantined')),
                reason TEXT,
                PRIMARY KEY(participant_id,event_id)
            );
            CREATE INDEX IF NOT EXISTS events_time ON events(participant_id,event_time,status);
            PRAGMA user_version=1;
        """)

    def close(self):
        with self.lock:
            self.db.close()

    def enroll(self, payload):
        exact_fields(payload, {"displayName", "realm", "casterClass", "consent"})
        if payload["consent"] is not True:
            invalid(
                "CONSENT_REQUIRED", "Die ausdrückliche Einwilligung consent:true fehlt."
            )
        display_name = public_name(payload["displayName"])
        realm = public_name(payload["realm"], realm=True)
        if payload["casterClass"] != "PALADIN":
            invalid(
                "CLASS_UNSUPPORTED",
                "Diese erste Version erfasst nur Paladinsegen über FMB.",
            )
        participant_id = uuid.uuid4().hex
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        identity_key = json.dumps([display_name.casefold(), realm.casefold()])
        try:
            with self.lock, self.db:
                self.db.execute(
                    "INSERT INTO participants VALUES (?,?,?,?,?,?,?,?)",
                    (
                        participant_id,
                        display_name,
                        realm,
                        identity_key,
                        "PALADIN",
                        token_hash,
                        int(self.clock()),
                        TRUST,
                    ),
                )
        except sqlite3.IntegrityError:
            raise ServiceError(
                409,
                "IDENTITY_EXISTS",
                "Dieser Name/Realm ist bereits angemeldet. Vorhandenen Zugang verwenden.",
            ) from None
        return {"participantId": participant_id, "token": token, "trust": TRUST}

    def authenticate(self, header):
        if (
            not isinstance(header, str)
            or not header.startswith("Bearer ")
            or len(header) > 128
        ):
            raise ServiceError(
                401,
                "AUTH_REQUIRED",
                "Gültigen Teilnehmerzugang als Bearer-Token senden.",
            )
        token = header[7:]
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            row = self.db.execute(
                "SELECT id FROM participants WHERE token_hash=?", (digest,)
            ).fetchone()
        if row is None:
            raise ServiceError(
                401,
                "AUTH_REQUIRED",
                "Gültigen Teilnehmerzugang als Bearer-Token senden.",
            )
        return row["id"]

    def ingest(self, participant_id, payload):
        exact_fields(payload, {"events"})
        events = payload["events"]
        if not isinstance(events, list) or not 1 <= len(events) <= MAX_BATCH:
            invalid(
                "BATCH_LIMIT",
                "Ein Upload muss 1 bis 100 einzelne Ereignisse enthalten.",
            )
        now = int(self.clock())
        for event in events:
            exact_fields(event, {"id", "spellId", "eventTime"})
            if not isinstance(event["id"], str) or not EVENT_ID.fullmatch(event["id"]):
                invalid(
                    "INVALID_EVENT_ID",
                    "Ereignis-ID: 8–96 ASCII-Buchstaben, Ziffern, Bindestriche oder Unterstriche.",
                )
            if type(event["spellId"]) is not int or event["spellId"] not in SPELLS:
                invalid(
                    "SPELL_UNSUPPORTED",
                    "Zauber-ID ist kein unterstützter normaler Paladinsegen.",
                )
            if (
                type(event["eventTime"]) is not int
                or not 0 <= event["eventTime"] <= 2**53 - 1
            ):
                invalid(
                    "INVALID_EVENT_TIME",
                    "eventTime muss eine ganze Unixzeit in Sekunden sein.",
                )
        result = {"accepted": 0, "duplicates": 0, "quarantined": 0, "trust": TRUST}
        with self.lock, self.db:
            # Sorting makes an out-of-order offline batch deterministic. Existing
            # earlier uploads retain their status; this is plausibility, not proof.
            for event in sorted(
                events, key=lambda item: (item["eventTime"], item["id"])
            ):
                existing = self.db.execute(
                    "SELECT spell_id,event_time FROM events WHERE participant_id=? AND event_id=?",
                    (participant_id, event["id"]),
                ).fetchone()
                if existing:
                    if (existing["spell_id"], existing["event_time"]) != (
                        event["spellId"],
                        event["eventTime"],
                    ):
                        raise ServiceError(
                            409,
                            "ID_CONFLICT",
                            "Eine vorhandene Ereignis-ID hat anderen Inhalt. Export prüfen.",
                        )
                    result["duplicates"] += 1
                    continue
                stamp = event["eventTime"]
                if not now - 7 * 86400 <= stamp <= now + 300:
                    invalid(
                        "EVENT_TIME_WINDOW",
                        "Neue Ereignisse dürfen höchstens sieben Tage alt oder fünf Minuten voraus sein.",
                    )
                reason = self._quarantine_reason(participant_id, stamp)
                event_status = "quarantined" if reason else "accepted"
                self.db.execute(
                    "INSERT INTO events VALUES (?,?,?,?,?,?,?,?)",
                    (
                        participant_id,
                        event["id"],
                        event["spellId"],
                        SPELLS[event["spellId"]],
                        stamp,
                        now,
                        event_status,
                        reason,
                    ),
                )
                result[event_status] += 1
        return result

    def _quarantine_reason(self, participant_id, stamp):
        # Buckets refer to the reported UTC time, not the upload minute: importing
        # yesterday's normal play should not be mistaken for a one-minute burst.
        for seconds, cap, reason in (
            (60, self.minute_limit, "MINUTE_LIMIT"),
            (86400, self.day_limit, "DAY_LIMIT"),
        ):
            start = stamp // seconds * seconds
            count = self.db.execute(
                """SELECT COUNT(*) FROM events WHERE participant_id=?
                AND status='accepted' AND event_time>=? AND event_time<?""",
                (participant_id, start, start + seconds),
            ).fetchone()[0]
            if count >= cap:
                return reason
        return None

    def profile(self, participant_id):
        """Let an authenticated browser show whose account it is about to change."""
        with self.lock:
            row = self.db.execute(
                "SELECT id,display_name,realm,caster_class FROM participants WHERE id=?",
                (participant_id,),
            ).fetchone()
        if row is None:
            raise ServiceError(
                401,
                "AUTH_REQUIRED",
                "Teilnehmerzugang wurde gelöscht oder ist ungültig.",
            )
        return {
            "participantId": row["id"],
            "displayName": row["display_name"],
            "realm": row["realm"],
            "casterClass": row["caster_class"],
            "trust": TRUST,
        }

    def delete(self, participant_id):
        with self.lock, self.db:
            self.db.execute("DELETE FROM participants WHERE id=?", (participant_id,))
        return {"deleted": True, "trust": TRUST}

    def leaderboard(self, query):
        allowed = {"group", "limit", "class", "buff"}
        if set(query) - allowed or any(len(values) != 1 for values in query.values()):
            invalid(
                "INVALID_QUERY",
                "Nur group, limit, class und buff, jeweils einmal, sind erlaubt.",
            )
        params = {key: values[0] for key, values in query.items()}
        group = params.get("group", "players")
        if group not in ("players", "classes", "buffs"):
            invalid("INVALID_GROUP", "group muss players, classes oder buffs sein.")
        limit_text = params.get("limit", "50")
        if (
            not re.fullmatch(r"[0-9]{1,3}", limit_text)
            or not 1 <= int(limit_text) <= 100
        ):
            invalid("INVALID_LIMIT", "limit muss zwischen 1 und 100 liegen.")
        where = ["e.status='accepted'"]
        arguments = []
        if "class" in params:
            if params["class"] != "PALADIN":
                invalid("CLASS_UNSUPPORTED", "Diese erste Version enthält nur PALADIN.")
            where.append("p.caster_class=?")
            arguments.append(params["class"])
        if "buff" in params:
            if params["buff"] not in BUFFS:
                invalid("BUFF_UNSUPPORTED", "buff muss might, wisdom oder kings sein.")
            where.append("e.buff=?")
            arguments.append(params["buff"])
        # SQL identifiers are constants selected above. All user values use binds.
        columns = {
            "players": "p.id,p.display_name,p.realm,p.caster_class",
            "classes": "p.caster_class",
            "buffs": "e.buff",
        }[group]
        clause = (
            " FROM events e JOIN participants p ON p.id=e.participant_id WHERE "
            + " AND ".join(where)
        )
        with self.lock:
            total = self.db.execute("SELECT COUNT(*)" + clause, arguments).fetchone()[0]
            records = self.db.execute(
                "SELECT "
                + columns
                + ",COUNT(*) AS count"
                + clause
                + " GROUP BY "
                + columns
                + " ORDER BY count DESC,"
                + columns
                + " LIMIT ?",
                [*arguments, int(limit_text)],
            ).fetchall()
        rows = []
        previous_count, rank = None, 0
        for position, record in enumerate(records, start=1):
            if record["count"] != previous_count:
                rank = position
            previous_count = record["count"]
            row = {"rank": rank, "count": record["count"], "trust": TRUST}
            if group == "players":
                row.update(
                    participantId=record["id"],
                    displayName=record["display_name"],
                    realm=record["realm"],
                    casterClass=record["caster_class"],
                )
            elif group == "classes":
                row["casterClass"] = record["caster_class"]
            else:
                row.update(
                    buff=record["buff"],
                    label=BUFFS[record["buff"]][0],
                    spellIds=list(BUFFS[record["buff"]][1]),
                )
            rows.append(row)
        return {
            "group": group,
            "rows": rows,
            "total": total,
            "trust": TRUST,
            "scope": "FMB-confirmed local casts; client claims, not game-server proof",
            "generatedAt": int(self.clock()),
        }


class RankingServer(ThreadingHTTPServer):
    """Bound HTTP workers share one short-transaction database connection."""

    daemon_threads = True
    request_queue_size = 32

    def __init__(self, address, db_path, *, clock=time.time, public_origin=None):
        self.store = Store(db_path, clock=clock)
        self.clock = clock
        self.limiter = RateLimiter(clock)
        self.public_origin = public_origin
        try:
            super().__init__(address, Handler)
        except Exception:
            self.store.close()
            raise
        port = self.server_address[1]
        self.allowed_origins = (
            {public_origin}
            if public_origin
            else {f"http://127.0.0.1:{port}", f"http://localhost:{port}"}
        )
        self.allowed_hosts = {
            urlsplit(origin).netloc for origin in self.allowed_origins
        }
        self.workers = threading.BoundedSemaphore(32)

    def process_request(self, request, client_address):
        if not self.workers.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.workers.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.workers.release()


class Handler(BaseHTTPRequestHandler):
    """Validate the wire format before crossing the persistent database boundary."""

    server_version = "FMBRanking/" + VERSION
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, format, *args):
        # BaseHTTPRequestHandler includes raw paths/IPs. Never write them to logs.
        return

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def do_DELETE(self):
        self._dispatch("DELETE")

    def _dispatch(self, method):
        try:
            self._check_origin()
            parsed = urlsplit(self.path)
            path = parsed.path
            if (
                method == "GET"
                and path
                in ("/", "/app.js", "/style.css", "/upload-core.js", "/upload.js")
                and not parsed.query
            ):
                files = {
                    "/": ("index.html", "text/html; charset=utf-8"),
                    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
                    "/style.css": ("style.css", "text/css; charset=utf-8"),
                    "/upload-core.js": (
                        "upload-core.js",
                        "text/javascript; charset=utf-8",
                    ),
                    "/upload.js": ("upload.js", "text/javascript; charset=utf-8"),
                }
                filename, mime = files[path]
                self._respond(200, (STATIC / filename).read_bytes(), mime)
                return
            if method == "GET" and path == "/health" and not parsed.query:
                self._json(200, {"ok": True, "version": VERSION, "trust": TRUST})
                return
            if method == "GET" and path == "/v1/leaderboard":
                try:
                    query = parse_qs(
                        parsed.query,
                        keep_blank_values=True,
                        strict_parsing=True,
                        max_num_fields=4,
                    )
                except ValueError:
                    invalid(
                        "INVALID_QUERY", "Ungültige Ranking-Filter. OpenAPI prüfen."
                    )
                self._json(200, self.server.store.leaderboard(query))
                return
            if method == "POST" and path == "/v1/participants" and not parsed.query:
                payload = self._read_json()
                self.server.limiter.check("enrollment", self.client_address[0], 8, 3600)
                self._json(201, self.server.store.enroll(payload))
                LOG.info("PARTICIPANT_ENROLLED")
                return
            if path in ("/v1/events", "/v1/participant") and not parsed.query:
                participant_id = self.server.store.authenticate(
                    self.headers.get("Authorization")
                )
                self.server.limiter.check("participant", participant_id, 120, 60)
                if method == "GET" and path == "/v1/participant":
                    self._json(200, self.server.store.profile(participant_id))
                    return
                if method == "POST" and path == "/v1/events":
                    result = self.server.store.ingest(participant_id, self._read_json())
                    self._json(200, result)
                    LOG.info(
                        "EVENT_BATCH accepted=%s duplicates=%s quarantined=%s",
                        result["accepted"],
                        result["duplicates"],
                        result["quarantined"],
                    )
                    return
                if method == "DELETE" and path == "/v1/participant":
                    if (
                        self.headers.get("Transfer-Encoding")
                        or self.headers.get("Content-Length", "0") != "0"
                    ):
                        invalid("DELETE_BODY", "DELETE benötigt keinen Request-Body.")
                    self._json(200, self.server.store.delete(participant_id))
                    LOG.info("PARTICIPANT_DELETED")
                    return
            raise ServiceError(404, "NOT_FOUND", "Dieser API-Pfad ist nicht vorhanden.")
        except ServiceError as error:
            self._json(
                error.status,
                {"error": error.code, "message": error.message, "trust": TRUST},
            )
            LOG.debug("REQUEST_REJECTED code=%s", error.code)
        except (sqlite3.Error, OSError, ValueError, OverflowError) as error:
            # Native exceptions may include filenames or submitted data. Only the
            # class is logged; the caller gets a stable, actionable error code.
            LOG.error("SERVICE_ERROR type=%s", type(error).__name__)
            self._json(
                503,
                {
                    "error": "SERVICE_UNAVAILABLE",
                    "message": "Dienstfehler. Lokale Logs und Datenbankrechte prüfen.",
                    "trust": TRUST,
                },
            )

    def _check_origin(self):
        hosts = self.headers.get_all("Host", [])
        origins = self.headers.get_all("Origin", [])
        if len(hosts) != 1 or hosts[0] not in self.server.allowed_hosts:
            raise ServiceError(
                403,
                "HOST_REJECTED",
                "Host passt nicht zur konfigurierten Dienstadresse.",
            )
        if len(origins) > 1 or (
            origins and origins[0] not in self.server.allowed_origins
        ):
            raise ServiceError(
                403,
                "ORIGIN_REJECTED",
                "Fremde Browser-Ursprünge sind nicht zugelassen.",
            )

    def _read_json(self):
        if self.headers.get("Transfer-Encoding"):
            invalid(
                "TRANSFER_ENCODING", "Content-Length statt Transfer-Encoding verwenden."
            )
        sizes = self.headers.get_all("Content-Length", [])
        if len(sizes) != 1 or not re.fullmatch(r"[0-9]{1,9}", sizes[0]):
            invalid(
                "CONTENT_LENGTH", "Eine eindeutige Content-Length ist erforderlich."
            )
        size = int(sizes[0])
        if size > MAX_BODY_BYTES:
            raise ServiceError(
                413,
                "BODY_LIMIT",
                "Upload überschreitet 32768 Bytes; kleinere Batches senden.",
            )
        if self.headers.get_content_type() != "application/json":
            raise ServiceError(
                415, "CONTENT_TYPE", "Content-Type application/json verwenden."
            )
        raw = self.rfile.read(size)
        if len(raw) != size:
            invalid("INCOMPLETE_BODY", "HTTP-Body ist unvollständig.")

        def unique_fields(pairs):
            value = {}
            for key, item in pairs:
                if key in value:
                    invalid(
                        "DUPLICATE_FIELD", "Doppelte JSON-Felder sind nicht erlaubt."
                    )
                value[key] = item
            return value

        def reject_constant(_):
            invalid("INVALID_JSON", "JSON darf weder NaN noch Infinity enthalten.")

        try:
            payload = json.loads(
                raw.decode("utf-8"),
                object_pairs_hook=unique_fields,
                parse_constant=reject_constant,
            )
        except (UnicodeError, ValueError, RecursionError):
            invalid("INVALID_JSON", "Body muss ein gültiges UTF-8-JSON-Objekt sein.")
        if not isinstance(payload, dict):
            invalid("INVALID_JSON", "Body muss ein JSON-Objekt sein.")
        return payload

    def _json(self, status, payload):
        self._respond(
            status,
            json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8"),
            "application/json; charset=utf-8",
        )

    def _respond(self, status, body, mime):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        )
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            LOG.debug("CLIENT_DISCONNECTED")


def main():
    parser = argparse.ArgumentParser(
        description="Lokales, nicht serverbestätigtes FMB-Community-Ranking"
    )
    parser.add_argument(
        "--host", default="127.0.0.1", help="Standard: nur dieser Rechner"
    )
    parser.add_argument("--port", default=18449, type=int)
    parser.add_argument("--db", default="data/ranking.sqlite3", type=Path)
    parser.add_argument(
        "--public-origin",
        help="Exakte HTTPS-Adresse eines vorgelagerten Reverse-Proxys",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Feste Diagnosecodes, niemals Tokens oder Namen",
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port muss zwischen 1 und 65535 liegen.")
    if args.public_origin:
        origin = urlsplit(args.public_origin)
        if (
            origin.scheme != "https"
            or not origin.hostname
            or origin.path
            or origin.query
            or origin.fragment
            or origin.username
            or origin.password
        ):
            parser.error(
                "--public-origin muss eine reine HTTPS-Origin ohne Pfad/Zugangsdaten sein."
            )
    if args.host not in ("127.0.0.1", "localhost") and not args.public_origin:
        parser.error(
            "Externe Bindung benötigt --public-origin und einen vorgeschalteten TLS-Reverse-Proxy."
        )
    os.umask(0o077)
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    try:
        if args.db.is_symlink():
            raise ValueError(
                "DB_PATH_INVALID: Keine Symlinks für die Datenbank verwenden."
            )
        args.db.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        server = RankingServer(
            (args.host, args.port), args.db, public_origin=args.public_origin
        )
    except (OSError, sqlite3.Error, ValueError) as error:
        LOG.error(
            "START_FAILED type=%s; Datenbankordner, Dateirechte und freien Port prüfen.",
            type(error).__name__,
        )
        return 1
    LOG.info(
        "STARTED version=%s port=%s trust=%s debug=%s",
        VERSION,
        args.port,
        TRUST,
        args.debug,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("STOP_REQUESTED")
    finally:
        server.server_close()
        server.store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
