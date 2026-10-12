"""Prepare a reviewed local source export and installable addon ZIP.

Input: project directory, new output directory and semantic version.
Output: source/, addon ZIP, source ZIP and SHA-256 inventory; no network activity.
Invariant: only the explicit own-code allowlist is eligible; validate all bytes
before writing. Hashes describe package integrity, never gameplay authenticity.
Debug: --debug logs fixed diagnostic codes and counts, never bodies or secrets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

LOG = logging.getLogger("fmb.release")
ADDON_NAMES = (
    "Core.lua",
    "API.lua",
    "Hash.lua",
    "CounterCodec.lua",
    "Stats.lua",
    "SpellLink.lua",
    "GreetingCatalog.lua",
    "Greetings.lua",
    "Recipient.lua",
    "Chat.lua",
    "RankingExport.lua",
    "Whisper.lua",
    "SealReminder.lua",
    "Diagnostics.lua",
    "App.lua",
    "ForeverMouseoverBuff.toc",
    "ForeverMouseoverBuff_Camelot.toc",
    "Bindings.xml",
)
PORTABLE_TESTS = (
    "test_core.lua",
    "test_api.lua",
    "test_counter_codec.lua",
    "test_stats.lua",
    "test_spell_link.lua",
    "test_ranking_export.lua",
    "test_greeting_catalog.lua",
    "test_greetings.lua",
    "test_recipient.lua",
    "test_whisper.lua",
    "test_seal_reminder.lua",
    "test_diagnostics.lua",
    "test_app.lua",
    "test_ranking_end_to_end.py",
    "test_diagnostics_end_to_end.py",
    "test_release_package.py",
)
# Exact names are deliberate: a new file must receive review before export.
SERVICE_FILES = (
    "server.py",
    "README.md",
    "CONTRIBUTING.md",
    "openapi.json",
    ".gitignore",
    "static/app.js",
    "static/style.css",
    "static/index.html",
    "tests/test_service.py",
    "static/upload-core.js",
    "static/upload.js",
    "tests/test_upload_core.cjs",
    "tests/test_upload_ui.cjs",
)
COMPANION_FILES = (
    "companion.py",
    "README.md",
    "CONTRIBUTING.md",
    "ruff.toml",
    ".gitignore",
    "fmb_companion/__init__.py",
    "fmb_companion/cli.py",
    "fmb_companion/client.py",
    "fmb_companion/errors.py",
    "fmb_companion/export.py",
    "fmb_companion/storage.py",
    "fmb_companion/browser_export.py",
    "fmb_companion/diagnostic_codes.py",
    "fmb_companion/diagnostics.py",
    "tests/test_companion.py",
    "tests/test_diagnostics.py",
)
TEMPLATE_FILES = (
    "README.md",
    "README.de.md",
    "BRANDING.md",
    "DIAGNOSTICS.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "LICENSE",
    ".gitignore",
    "CHANGELOG.md",
    ".github/workflows/ci.yml",
    "scripts/check-portable.sh",
    "curseforge/description-en.md",
    "curseforge/description-de.md",
    "curseforge/submission.md",
    "curseforge/metadata.json",
)
OPTIONAL_ASSETS = (
    "assets/feberdin-knight.png",
    "assets/project-icon.svg",
    "assets/project-icon.png",
    "assets/brand-banner.svg",
    "assets/brand-banner.png",
    "assets/social-preview.svg",
    "assets/social-preview.png",
    "assets/how-it-works.svg",
    "assets/how-it-works.png",
    "assets/curseforge-banner.svg",
    "assets/curseforge-banner.png",
)
MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_TOTAL_BYTES = 20 * 1024 * 1024
PRIVATE_PATH = re.compile(rb"/(?:Users|Volumes|Applications)/")
CREDENTIAL = re.compile(
    rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|"
    rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
    rb"(?:CURSEFORGE_API_KEY|UNRAID_DEPLOY_BROKER_TOKEN)\s*[=:]\s*[\"']?[A-Za-z0-9_-]{20,})"
)


class ReleaseError(Exception):
    """Known validation/write failure, exposing a fixed safe code only."""


def source_mapping() -> dict[str, str]:
    """Map eligible source inputs to portable public-repository destinations."""
    mapping = {
        f"src/ForeverMouseoverBuff/{name}": f"src/ForeverMouseoverBuff/{name}"
        for name in ADDON_NAMES
    }
    for directory, names in (
        ("tests", PORTABLE_TESTS),
        ("service", SERVICE_FILES),
        ("companion", COMPANION_FILES),
    ):
        mapping.update({f"{directory}/{name}": f"{directory}/{name}" for name in names})
    mapping["scripts/prepare-release.py"] = "scripts/prepare-release.py"
    # Templates are copied both as public root files and reproducible release inputs.
    mapping.update({f"release/{name}": name for name in TEMPLATE_FILES})
    return mapping


def read_reviewed_file(project: Path, relative: str) -> bytes:
    """Reject links, private paths and recognizable credentials before export."""
    path = project / relative
    for candidate in (path, *path.parents):
        if candidate == project:
            break
        if candidate.is_symlink():
            raise ReleaseError(
                "SOURCE_SYMLINK: Replace linked release inputs with reviewed regular files."
            )
    if not path.is_file():
        raise ReleaseError(
            "SOURCE_MISSING: A required allowlisted input is missing; restore the complete source tree."
        )
    if path.stat().st_size > MAX_FILE_BYTES:
        raise ReleaseError(
            "SOURCE_TOO_LARGE: Review the unexpectedly large release input."
        )
    data = path.read_bytes()
    if not data:
        raise ReleaseError(
            "SOURCE_EMPTY: A required input is empty; review it before export."
        )
    if PRIVATE_PATH.search(data) or CREDENTIAL.search(data):
        raise ReleaseError(
            "SOURCE_PRIVATE_DATA: Remove local computer paths or credentials from the reviewed inputs."
        )
    return data


def collect_payload(project: Path, version: str) -> dict[str, bytes]:
    """Read an immutable snapshot so concurrent edits cannot change packaged bytes."""
    payload = {}
    for relative, destination in source_mapping().items():
        data = read_reviewed_file(project, relative)
        payload[destination] = data
        if relative.startswith("release/"):
            payload[relative] = data
    for relative in OPTIONAL_ASSETS:
        source = project / "release" / relative
        if source.exists() or source.is_symlink():
            payload[f"release/{relative}"] = read_reviewed_file(
                project, f"release/{relative}"
            )
    if sum(map(len, payload.values())) > MAX_TOTAL_BYTES:
        raise ReleaseError(
            "SOURCE_TOO_LARGE: Total release size exceeds the reviewed bound."
        )
    for name in ("ForeverMouseoverBuff.toc", "ForeverMouseoverBuff_Camelot.toc"):
        text = payload[f"src/ForeverMouseoverBuff/{name}"].decode("utf-8")
        match = re.search(r"^## Version:\s*(\S+)\s*$", text, re.MULTILINE)
        if not match or match.group(1) != version:
            raise ReleaseError(
                "VERSION_MISMATCH: Both addon manifests must match --version exactly."
            )
        loaded = [
            line.strip()
            for line in text.splitlines()
            if line.strip() and not line.startswith("#")
        ]
        if loaded != [name for name in ADDON_NAMES if name.endswith(".lua")]:
            raise ReleaseError(
                "TOC_INPUT_MISMATCH: Review manifest entries and the package allowlist together."
            )
    if (
        payload["src/ForeverMouseoverBuff/ForeverMouseoverBuff.toc"]
        != payload["src/ForeverMouseoverBuff/ForeverMouseoverBuff_Camelot.toc"]
    ):
        raise ReleaseError("TOC_MISMATCH: Synchronize both manifests before packaging.")
    return payload


def write_zip(path: Path, payload: dict[str, bytes]) -> None:
    """Write stable sorted bytes without host timestamps, permissions or paths."""
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(payload.items()):
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)


def prepare_release(project: Path, output: Path, version: str) -> dict:
    """Export new artifacts atomically; an existing output is never overwritten."""
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ReleaseError("VERSION_INVALID: Use a numeric version such as 0.7.0.")
    project = project.resolve(strict=True)
    if not project.is_dir():
        raise ReleaseError("PROJECT_INVALID: Select the source project directory.")
    if output.is_symlink() or output.exists():
        raise ReleaseError(
            "OUTPUT_EXISTS: Choose a new output directory; existing artifacts are preserved."
        )
    output = output.absolute()
    if not output.parent.is_dir():
        raise ReleaseError(
            "OUTPUT_PARENT_MISSING: Create the intended parent directory first."
        )
    if output.parent.is_symlink():
        raise ReleaseError(
            "OUTPUT_SYMLINK: Choose an output parent that is a real directory."
        )
    payload = collect_payload(project, version)
    addon = {
        f"ForeverMouseoverBuff/{name}": payload[f"src/ForeverMouseoverBuff/{name}"]
        for name in ADDON_NAMES
    }
    addon["ForeverMouseoverBuff/LICENSE"] = payload["LICENSE"]
    result = {
        "version": version,
        "source_files": sorted(payload),
        "addon_files": sorted(addon),
        "source_sha256": {
            name: hashlib.sha256(data).hexdigest()
            for name, data in sorted(payload.items())
        },
        "addon_sha256": {
            name: hashlib.sha256(data).hexdigest()
            for name, data in sorted(addon.items())
        },
        "scope": "local preparation only; no upload or Git remote configured",
    }
    # Staging protects reviewable prior artifacts when writes fail midway.
    staging = Path(tempfile.mkdtemp(prefix=".fmb-release-", dir=output.parent))
    try:
        for name, data in payload.items():
            target = staging / "source" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        write_zip(staging / f"ForeverMouseoverBuff-{version}.zip", addon)
        write_zip(
            staging / f"ForeverMouseoverBuff-{version}-source.zip",
            {f"ForeverMouseoverBuff/{name}": data for name, data in payload.items()},
        )
        (staging / "manifest.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8"
        )
        if output.exists() or output.is_symlink():
            raise ReleaseError(
                "OUTPUT_EXISTS: Destination changed during preparation; retry with a new directory."
            )
        staging.rename(output)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    LOG.info(
        "RELEASE_PREPARED source_files=%d addon_files=%d", len(payload), len(addon)
    )
    return result


def main() -> int:
    """Safe CLI wrapper: log codes rather than filesystem content or tracebacks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New local directory; never overwritten.",
    )
    parser.add_argument("--version", required=True)
    parser.add_argument("--debug", action="store_true")
    arguments = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if arguments.debug else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    try:
        prepare_release(arguments.project, arguments.output, arguments.version)
    except ReleaseError as error:
        LOG.error("%s", error)
        return 2
    except (OSError, UnicodeError, ValueError) as error:
        LOG.error(
            "RELEASE_IO_FAILED type=%s; check source/output access and retry.",
            type(error).__name__,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
