"""Read-only stable game snapshots; atomic private credentials outside game paths.

Input: explicit local paths. Output: bytes/config or sanitized CompanionError.
No Lua writes, symlink following, secret logging, config replacement or implicit chmod.
Debug fixed SOURCE_*/CONFIG_* codes; temp configs have 0600, private parent 0700.
"""

import json
import os
import re
import stat
import tempfile
from pathlib import Path

from .errors import CompanionError
from .export import FILE_LIMIT, strict_json


def checked_path(path):
    try:
        path = Path(path).expanduser()
        if ".." in path.parts:
            raise CompanionError("PATH_INVALID")
        path = Path(os.path.abspath(path))
        for part in reversed((path, *path.parents)):
            if part.is_symlink():
                raise CompanionError("PATH_SYMLINK")
        return path
    except (OSError, ValueError, TypeError):
        raise CompanionError("PATH_INVALID") from None


def signature(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_stable(path, limit=FILE_LIMIT):
    """Observe size/inode/timestamps before and after one bounded O_RDONLY read."""
    path = checked_path(path)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise CompanionError("SOURCE_INVALID")
            if before.st_size > limit:
                raise CompanionError("SOURCE_TOO_LARGE")
            data = stream.read(limit + 1)
            after = os.fstat(stream.fileno())
        final = path.lstat()
        if (
            signature(before) != signature(after)
            or signature(after) != signature(final)
            or len(data) != before.st_size
        ):
            raise CompanionError("SOURCE_UNSTABLE")
        if len(data) > limit:
            raise CompanionError("SOURCE_TOO_LARGE")
        return data
    except OSError:
        raise CompanionError("SOURCE_UNAVAILABLE") from None


def validate_config_path(path, source):
    path, source = checked_path(path), checked_path(source)
    forbidden = {
        "wow",
        "world of warcraft",
        "wtf",
        "interface",
        "addons",
        "_classic_beta_",
        "_classic_era_",
        "_retail_",
    }
    if any(part.casefold() in forbidden for part in path.parts) or path.is_relative_to(
        source.parent
    ):
        raise CompanionError("CONFIG_LOCATION")
    return path


def private_parent(path):
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        parent = checked_path(path.parent).stat()
        if (
            not stat.S_ISDIR(parent.st_mode)
            or stat.S_IMODE(parent.st_mode) != 0o700
            or parent.st_uid != os.getuid()
        ):
            raise CompanionError("CONFIG_PERMISSIONS")
    except OSError:
        raise CompanionError("CONFIG_UNAVAILABLE") from None


def prepare_config(path, source):
    path = validate_config_path(path, source)
    if path.exists():
        raise CompanionError("CONFIG_EXISTS")
    private_parent(path)
    return path


def validate_config(data):
    keys = {"schema", "endpoint", "savedVariables", "participantId", "token", "consent"}
    if (
        type(data) is not dict
        or set(data) != keys
        or type(data["schema"]) is not int
        or data["schema"] != 1
        or data["consent"] is not True
        or type(data["endpoint"]) is not str
        or len(data["endpoint"]) > 2048
        or type(data["savedVariables"]) is not str
        or not 1 <= len(data["savedVariables"]) <= 4096
        or type(data["participantId"]) is not str
        or not re.fullmatch(r"[0-9a-f]{32}", data["participantId"])
        or type(data["token"]) is not str
        or not re.fullmatch(r"[A-Za-z0-9_-]{43}", data["token"])
    ):
        raise CompanionError("CONFIG_INVALID")
    return data


def load_config(path):
    path = checked_path(path)
    try:
        info = path.lstat()
        parent = path.parent.stat()
        if (
            not stat.S_ISREG(info.st_mode)
            or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(parent.st_mode) != 0o700
            or parent.st_uid != os.getuid()
        ):
            raise CompanionError("CONFIG_PERMISSIONS")
        result = validate_config(strict_json(read_stable(path, limit=16384), "CONFIG_INVALID"))
        validate_config_path(path, result["savedVariables"])
        return result
    except OSError:
        raise CompanionError("CONFIG_UNAVAILABLE") from None


def save_config(path, data):
    data = validate_config(data)
    path = prepare_config(path, data["savedVariables"])
    temporary = None
    try:
        fd, temporary = tempfile.mkstemp(prefix=".participant-", dir=path.parent)
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(json.dumps(data, separators=(",", ":")).encode())
            stream.flush()
            os.fsync(stream.fileno())
        # link creates the final name atomically without replacing an existing
        # file. Unlinking the private temporary leaves exactly one file link.
        os.link(temporary, path, follow_symlinks=False)
        os.unlink(temporary)
        temporary = None
        return path
    except FileExistsError:
        raise CompanionError("CONFIG_EXISTS") from None
    except OSError:
        raise CompanionError("CONFIG_WRITE_FAILED") from None
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                # No native pathname/exception may expose token storage context.
                raise CompanionError("CONFIG_TEMP_CLEANUP_FAILED") from None


def remove_config(path, expected):
    if load_config(path) != expected:
        raise CompanionError("CONFIG_CHANGED")
    try:
        checked_path(path).unlink()
    except OSError:
        raise CompanionError("CONFIG_REMOVE_FAILED") from None
