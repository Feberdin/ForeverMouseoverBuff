"""Create a minimal ranking JSON file for voluntary browser upload, entirely locally.

Input: explicit SavedVariables path and a new .json destination. Output: known FMB
export fields only, with 0600 rights. Never execute Lua, enroll, contact a network,
overwrite files, persist access tokens or echo source paths in logs.
Debug: fixed OUTPUT_*/EXPORT_* codes; companion/tests/test_companion.py.
"""

import json
import os

from .errors import CompanionError
from .export import parse_saved_variables
from .storage import checked_path, read_stable


def write_browser_export(source, destination):
    """Reuse the reviewed literal parser; publish exclusively to a new user path."""
    source = checked_path(source)
    destination = checked_path(destination)
    if destination == source or destination.suffix.lower() != ".json":
        raise CompanionError("OUTPUT_LOCATION")
    if destination.exists():
        raise CompanionError("OUTPUT_EXISTS")
    if not destination.parent.is_dir():
        raise CompanionError("OUTPUT_UNAVAILABLE")
    value = parse_saved_variables(read_stable(source))
    payload = (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode(
            "utf-8"
        )
        + b"\n"
    )
    created = False
    try:
        descriptor = os.open(
            destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
        created = True
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        raise CompanionError("OUTPUT_EXISTS") from None
    except OSError:
        if created:
            try:
                destination.unlink()
            except OSError:
                raise CompanionError("OUTPUT_CLEANUP_FAILED") from None
        raise CompanionError("OUTPUT_UNAVAILABLE") from None
    return {
        "status": "EXPORT_WRITTEN",
        "enabled": value["enabled"],
        "events": len(value["events"]),
        "trust": "self_reported",
    }
