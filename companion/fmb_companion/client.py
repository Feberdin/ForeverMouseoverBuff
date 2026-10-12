"""Explicit self-reported community enrollment, bounded sync and confirmed leave.

Input: validated local export/private config. Output: anonymous result counts.
Only HTTPS or loopback, no redirects/proxy inheritance, no automatic enrollment.
Debug fixed codes; token, identities, payloads and native exceptions stay private.
"""

import ipaddress
import json
import math
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

from .errors import CompanionError
from .export import parse_saved_variables, strict_json
from .storage import (
    checked_path,
    load_config,
    prepare_config,
    read_stable,
    remove_config,
    save_config,
)


def validate_endpoint(value):
    if type(value) is not str or len(value) > 2048 or any(char.isspace() for char in value):
        raise CompanionError("ENDPOINT_INVALID")
    try:
        uri = urllib.parse.urlsplit(value)
        host, port = uri.hostname, uri.port
        if (
            uri.scheme not in ("http", "https")
            or not host
            or uri.username is not None
            or uri.password is not None
            or uri.query
            or uri.fragment
            or uri.path not in ("", "/")
            or (port is not None and not 1 <= port <= 65535)
        ):
            raise CompanionError("ENDPOINT_INVALID")
        loopback = host.lower() == "localhost"
        try:
            loopback = loopback or ipaddress.ip_address(host).is_loopback
        except ValueError:
            if not re.fullmatch(r"[A-Za-z0-9.-]+", host):
                raise CompanionError("ENDPOINT_INVALID") from None
        if uri.scheme == "http" and not loopback:
            raise CompanionError("ENDPOINT_INVALID")
        return value.rstrip("/")
    except ValueError:
        raise CompanionError("ENDPOINT_INVALID") from None


def display_name(value, realm=False):
    if type(value) is not str:
        raise CompanionError("IDENTITY_INVALID")
    value = unicodedata.normalize("NFC", value)
    allowed = " '-_" if realm else " '-"
    try:
        valid = (
            value == value.strip()
            and 2 <= len(value) <= 64
            and len(value.encode("utf-8")) <= 96
            and any(c.isalpha() for c in value)
            and all(c.isalpha() or c in allowed or (realm and c.isdigit()) for c in value)
        )
    except UnicodeError:
        valid = False
    if not valid:
        raise CompanionError("IDENTITY_INVALID")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CompanionError("ENDPOINT_REDIRECT")


class HTTPTransport:
    """The sole network boundary: bounded JSON, TLS defaults, ten-second timeout."""

    def request(self, method, endpoint, path, body=None, token=None):
        endpoint = validate_endpoint(endpoint)
        if (method, path) not in (
            ("POST", "/v1/participants"),
            ("POST", "/v1/events"),
            ("DELETE", "/v1/participant"),
        ):
            raise CompanionError("REQUEST_INVALID")
        if token is not None and (
            type(token) is not str or not re.fullmatch(r"[A-Za-z0-9_-]{43}", token)
        ):
            raise CompanionError("CONFIG_INVALID")
        payload = (
            json.dumps(body, separators=(",", ":"), allow_nan=False).encode()
            if body is not None
            else None
        )
        if payload is not None and len(payload) > 32768:
            raise CompanionError("REQUEST_TOO_LARGE")
        headers = {"Accept": "application/json", "User-Agent": "FMB-Companion/1.0"}
        if payload is not None:
            headers.update(
                {
                    "Content-Type": "application/json",
                    "Content-Length": str(len(payload)),
                }
            )
        if token is not None:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(
            endpoint + path, data=payload, headers=headers, method=method
        )
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            with opener.open(request, timeout=10) as response:
                if response.headers.get_content_type() != "application/json":
                    raise CompanionError("RESPONSE_INVALID")
                raw = response.read(32769)
                if len(raw) > 32768:
                    raise CompanionError("RESPONSE_INVALID")
                return response.status, strict_json(raw, "RESPONSE_INVALID")
        except urllib.error.HTTPError as error:
            code = {
                400: "SERVER_VALIDATION",
                401: "AUTH_REQUIRED",
                409: "SERVER_CONFLICT",
                429: "RATE_LIMITED",
            }.get(error.code)
            if 300 <= error.code < 400:
                code = "ENDPOINT_REDIRECT"
            error.close()
            raise CompanionError(code or "SERVER_ERROR") from None
        except (urllib.error.URLError, OSError, TimeoutError):
            raise CompanionError("NETWORK_UNAVAILABLE") from None


def response_shape(status, value, wanted_status, keys):
    if (
        status != wanted_status
        or type(value) is not dict
        or set(value) != keys
        or value.get("trust") != "self_reported"
    ):
        raise CompanionError("RESPONSE_INVALID")


class Companion:
    def __init__(self, transport=None, clock=None):
        self.transport, self.clock = transport or HTTPTransport(), clock or time.time

    def enroll(self, endpoint, name, realm, source, config, consent=False):
        if consent is not True:
            raise CompanionError("CONSENT_REQUIRED")
        endpoint = validate_endpoint(endpoint)
        name, realm = display_name(name), display_name(realm, realm=True)
        source = checked_path(source)
        prepare_config(config, source)
        parse_saved_variables(read_stable(source))
        status, response = self.transport.request(
            "POST",
            endpoint,
            "/v1/participants",
            {
                "displayName": name,
                "realm": realm,
                "casterClass": "PALADIN",
                "consent": True,
            },
        )
        response_shape(status, response, 201, {"participantId", "token", "trust"})
        if (
            type(response["participantId"]) is not str
            or not re.fullmatch(r"[a-f0-9]{32}", response["participantId"])
            or type(response["token"]) is not str
            or not re.fullmatch(r"[A-Za-z0-9_-]{43}", response["token"])
        ):
            raise CompanionError("RESPONSE_INVALID")
        data = {
            "schema": 1,
            "endpoint": endpoint,
            "savedVariables": str(source),
            "participantId": response["participantId"],
            "token": response["token"],
            "consent": True,
        }
        try:
            save_config(config, data)
        except CompanionError:
            # If local persistence fails after enrollment, compensate with one
            # deletion request. Never print the otherwise lost token as recovery.
            try:
                status, response = self.transport.request(
                    "DELETE", endpoint, "/v1/participant", token=data["token"]
                )
                response_shape(status, response, 200, {"deleted", "trust"})
                if response["deleted"] is not True:
                    raise CompanionError("RESPONSE_INVALID")
            except CompanionError:
                raise CompanionError("ENROLL_SAVE_AND_CLEANUP_FAILED") from None
            raise CompanionError("ENROLL_SAVE_FAILED_ROLLED_BACK") from None
        return {"status": "ENROLLED", "trust": "self_reported"}

    def sync(self, config):
        cfg = load_config(config)
        endpoint = validate_endpoint(cfg["endpoint"])
        data = parse_saved_variables(read_stable(cfg["savedVariables"]))
        result = {
            "status": "SYNCED",
            "accepted": 0,
            "duplicates": 0,
            "quarantined": 0,
            "expired": 0,
            "trust": "self_reported",
        }
        if not data["enabled"]:
            result["status"] = "EXPORT_DISABLED"
            return result
        stamp = self.clock()
        if (
            type(stamp) not in (int, float)
            or not math.isfinite(stamp)
            or not 1 <= stamp <= 4102444800
        ):
            raise CompanionError("CLOCK_INVALID")
        if any(event["eventTime"] > stamp + 300 for event in data["events"]):
            raise CompanionError("CLOCK_SKEW")
        events = [event for event in data["events"] if event["eventTime"] >= stamp - 604800]
        result["expired"] = len(data["events"]) - len(events)
        for offset in range(0, len(events), 100):
            batch = events[offset : offset + 100]
            status, response = self.transport.request(
                "POST", endpoint, "/v1/events", {"events": batch}, cfg["token"]
            )
            response_shape(
                status,
                response,
                200,
                {"accepted", "duplicates", "quarantined", "trust"},
            )
            counts = [response[key] for key in ("accepted", "duplicates", "quarantined")]
            if any(type(count) is not int or count < 0 for count in counts) or sum(counts) != len(
                batch
            ):
                raise CompanionError("RESPONSE_INVALID")
            for key in ("accepted", "duplicates", "quarantined"):
                result[key] += response[key]
        return result

    def leave(self, config):
        cfg = load_config(config)
        status, response = self.transport.request(
            "DELETE",
            validate_endpoint(cfg["endpoint"]),
            "/v1/participant",
            token=cfg["token"],
        )
        response_shape(status, response, 200, {"deleted", "trust"})
        if response["deleted"] is not True:
            raise CompanionError("RESPONSE_INVALID")
        remove_config(config, cfg)
        return {"status": "LEFT", "trust": "self_reported"}

    def watch(self, config, interval=10, stop=None, sleep=None, report=None):
        if (
            type(interval) not in (int, float)
            or not math.isfinite(interval)
            or not 10 <= interval <= 86400
        ):
            raise CompanionError("POLL_INTERVAL")
        stop, sleep, report = (
            stop or (lambda: False),
            sleep or time.sleep,
            report or (lambda _: None),
        )
        retryable = {
            "SOURCE_UNAVAILABLE",
            "SOURCE_UNSTABLE",
            "EXPORT_SYNTAX",
            "EXPORT_MISSING",
            "NETWORK_UNAVAILABLE",
            "RATE_LIMITED",
            "SERVER_ERROR",
        }
        while not stop():
            try:
                result = self.sync(config)
            except CompanionError as error:
                if error.code not in retryable:
                    raise
                result = {"status": error.code}
            report(result)
            if not stop():
                sleep(interval)
