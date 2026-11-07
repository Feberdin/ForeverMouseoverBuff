"""Release allowlist contracts with synthetic files and private-data canaries.

Input: temporary project trees. Output: deterministic package/security assertions.
Invariant: no user SavedVariables, real secrets, game files or network requests.
Debug: python3 -m unittest discover -s tests -p test_release_package.py -v.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "fmb_prepare_release",
    Path(__file__).resolve().parents[1] / "scripts/prepare-release.py",
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "project"
        self.root.mkdir()
        self.output = self.base / "release"
        for relative in release.source_mapping():
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("reviewed synthetic source\n", encoding="utf-8")
        self.toc = (
            "## Version: 0.7.0\n"
            + "\n".join(name for name in release.ADDON_NAMES if name.endswith(".lua"))
            + "\n"
        )
        for name in ("ForeverMouseoverBuff.toc", "ForeverMouseoverBuff_Camelot.toc"):
            (self.root / "src/ForeverMouseoverBuff" / name).write_text(
                self.toc, encoding="utf-8"
            )

    def prepare(self):
        return release.prepare_release(self.root, self.output, "0.7.0")

    def assert_rejected(self, code):
        with self.assertRaisesRegex(release.ReleaseError, code):
            self.prepare()
        self.assertFalse(
            self.output.exists(), "Invalid input must create no final artifact."
        )

    def test_export_contains_own_addon_and_excludes_private_unlisted_files(self):
        for relative in (
            "SavedVariables.lua",
            ".env",
            "backups/secret.lua",
            "src/ForeverMouseoverBuff/unreviewed.lua",
            "docs/native/wow.lua",
        ):
            file = self.root / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("private synthetic fixture\n", encoding="utf-8")
        result = self.prepare()
        self.assertIn("src/ForeverMouseoverBuff/Core.lua", result["source_files"])
        self.assertNotIn("SavedVariables.lua", result["source_files"])
        self.assertNotIn(
            "src/ForeverMouseoverBuff/unreviewed.lua", result["source_files"]
        )
        self.assertEqual(
            result["source_files"],
            sorted(
                file.relative_to(self.output / "source").as_posix()
                for file in (self.output / "source").rglob("*")
                if file.is_file()
            ),
        )
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as archive:
            self.assertEqual(archive.namelist(), sorted(result["addon_files"]))
            self.assertIn("ForeverMouseoverBuff/LICENSE", archive.namelist())
            self.assertEqual(len(archive.namelist()), len(release.ADDON_NAMES) + 1)
        self.assertEqual(
            json.loads((self.output / "manifest.json").read_text()), result
        )

    def test_auto_thanks_and_existing_attempt_trace_ship_in_addon(self):
        for name in ("AutoThanks.lua", "AttemptTrace.lua"):
            self.assertIn(name, release.ADDON_NAMES)
        self.assertIn("test_auto_thanks.lua", release.PORTABLE_TESTS)

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("keep me")
        with self.assertRaisesRegex(release.ReleaseError, "OUTPUT_EXISTS"):
            self.prepare()
        self.assertEqual(marker.read_text(), "keep me")

    def test_launch_artwork_ships_in_source_without_inflating_game_addon(self):
        # Public release images belong to the developer archive, never the game UI.
        names = [
            "hero-art-0.9.0.jpg",
            "launch-0.9.0.html",
            "launch-0.9.0.md",
            "render-launch-0.9.0.py",
        ]
        for view in ("hero", "intro", "keybinding"):
            names.extend(f"launch-{view}-0.9.0.{ext}" for ext in ("png", "svg"))
        for name in names:
            target = self.root / "release/assets" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"synthetic public artwork")
        result = self.prepare()
        for name in names:
            self.assertIn("release/assets/" + name, result["source_files"])
            self.assertFalse(any(name in path for path in result["addon_files"]))

    def test_counter_helpers_ship_and_load_before_statistics(self):
        self.prepare()
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as archive:
            for helper in ("Hash.lua", "CounterCodec.lua"):
                self.assertIn("ForeverMouseoverBuff/" + helper, archive.namelist())
            for manifest in (
                "ForeverMouseoverBuff.toc",
                "ForeverMouseoverBuff_Camelot.toc",
            ):
                lines = (
                    archive.read("ForeverMouseoverBuff/" + manifest)
                    .decode()
                    .splitlines()
                )
                self.assertLess(
                    lines.index("Hash.lua"), lines.index("CounterCodec.lua")
                )
                self.assertLess(
                    lines.index("CounterCodec.lua"), lines.index("Stats.lua")
                )

    def test_invalid_version_cannot_escape_archive_name(self):
        with self.assertRaisesRegex(release.ReleaseError, "VERSION_INVALID"):
            release.prepare_release(self.root, self.output, "../outside")
        self.assertFalse(self.output.exists())

    def test_diagnostics_ship_in_addon_and_load_before_app(self):
        self.prepare()
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as archive:
            self.assertIn("ForeverMouseoverBuff/Diagnostics.lua", archive.namelist())
            for manifest in (
                "ForeverMouseoverBuff.toc",
                "ForeverMouseoverBuff_Camelot.toc",
            ):
                lines = (
                    archive.read("ForeverMouseoverBuff/" + manifest)
                    .decode()
                    .splitlines()
                )
                self.assertLess(lines.index("Diagnostics.lua"), lines.index("App.lua"))

    def test_shared_diagnostics_ships_before_core_in_both_manifests(self):
        # This module is a real TOC dependency, independent of the package list.
        # Reproduce the missing-allowlist bug rather than deriving the expectation
        # from ADDON_NAMES, which previously hid the packaging mismatch.
        module = self.root / "src/ForeverMouseoverBuff/FeberdinDiagnostics.lua"
        module.write_text("-- synthetic shared diagnostics module\n", encoding="utf-8")
        for name in ("ForeverMouseoverBuff.toc", "ForeverMouseoverBuff_Camelot.toc"):
            toc = self.root / "src/ForeverMouseoverBuff" / name
            lines = [
                line
                for line in toc.read_text().splitlines()
                if line != "FeberdinDiagnostics.lua"
            ]
            lines.insert(lines.index("Core.lua"), "FeberdinDiagnostics.lua")
            toc.write_text("\n".join(lines) + "\n", encoding="utf-8")

        result = self.prepare()
        self.assertIn(
            "src/ForeverMouseoverBuff/FeberdinDiagnostics.lua", result["source_files"]
        )
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as archive:
            self.assertEqual(
                archive.read("ForeverMouseoverBuff/FeberdinDiagnostics.lua"),
                module.read_bytes(),
            )
            for name in (
                "ForeverMouseoverBuff.toc",
                "ForeverMouseoverBuff_Camelot.toc",
            ):
                lines = (
                    archive.read("ForeverMouseoverBuff/" + name).decode().splitlines()
                )
                self.assertLess(
                    lines.index("FeberdinDiagnostics.lua"), lines.index("Core.lua")
                )

    def test_local_diagnostic_reader_ships_only_in_source(self):
        result = self.prepare()
        for name in (
            "fmb_companion/diagnostics.py",
            "fmb_companion/diagnostic_codes.py",
            "tests/test_diagnostics.py",
        ):
            self.assertIn("companion/" + name, result["source_files"])
            self.assertFalse(any(name in path for path in result["addon_files"]))

    def test_sanctum_menu_ships_with_native_theme_and_required_runtime_logos(self):
        result = self.prepare()
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as addon:
            for name in (
                "Keybinding.lua",
                "Theme.lua",
                "Menu.lua",
                "Media/ProjectIcon.tga",
                "Media/FeberdinKnight.tga",
            ):
                self.assertIn("ForeverMouseoverBuff/" + name, addon.namelist())
                self.assertEqual(
                    addon.read("ForeverMouseoverBuff/" + name),
                    (self.root / "src/ForeverMouseoverBuff" / name).read_bytes(),
                )
                self.assertIn(
                    "src/ForeverMouseoverBuff/" + name, result["source_files"]
                )
            for name in (
                "ForeverMouseoverBuff.toc",
                "ForeverMouseoverBuff_Camelot.toc",
            ):
                toc = addon.read("ForeverMouseoverBuff/" + name).decode().splitlines()
                self.assertLess(toc.index("Theme.lua"), toc.index("Menu.lua"))
                self.assertLess(toc.index("Theme.lua"), toc.index("FeedbackUI.lua"))
                self.assertLess(toc.index("Menu.lua"), toc.index("App.lua"))

    def test_feedback_modules_and_forms_ship_at_the_correct_boundaries(self):
        result = self.prepare()
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as archive:
            for name in ("Feedback.lua", "FeedbackUI.lua"):
                self.assertIn("ForeverMouseoverBuff/" + name, archive.namelist())
            toc = (
                archive.read("ForeverMouseoverBuff/ForeverMouseoverBuff.toc")
                .decode()
                .splitlines()
            )
            self.assertLess(toc.index("Diagnostics.lua"), toc.index("Feedback.lua"))
            self.assertLess(toc.index("Feedback.lua"), toc.index("FeedbackUI.lua"))
            self.assertLess(toc.index("FeedbackUI.lua"), toc.index("App.lua"))
        for name in ("01-bug.yml", "02-wish.yml", "03-feature.yml", "config.yml"):
            self.assertIn(".github/ISSUE_TEMPLATE/" + name, result["source_files"])
            self.assertNotIn("ForeverMouseoverBuff/" + name, result["addon_files"])
        self.assertIn("docs/feedback.md", result["source_files"])

    def test_missing_required_source_fails_before_writing(self):
        (self.root / "src/ForeverMouseoverBuff/Core.lua").unlink()
        self.assert_rejected("SOURCE_MISSING")

    def test_symlinked_source_file_is_rejected(self):
        source = self.root / "src/ForeverMouseoverBuff/Core.lua"
        source.unlink()
        outsider = self.base / "private.lua"
        outsider.write_text("private synthetic data")
        source.symlink_to(outsider)
        self.assert_rejected("SOURCE_SYMLINK")

    def test_symlinked_parent_of_source_file_is_rejected(self):
        source = self.root / "src/ForeverMouseoverBuff"
        outsider = self.base / "source-elsewhere"
        source.rename(outsider)
        source.symlink_to(outsider, target_is_directory=True)
        self.assert_rejected("SOURCE_SYMLINK")

    def test_private_absolute_path_is_rejected_without_echoing_content(self):
        private = "/" + "Users" + "/synthetic/hidden"
        (self.root / "src/ForeverMouseoverBuff/Core.lua").write_text(private)
        self.assert_rejected("SOURCE_PRIVATE_DATA")

    def test_recognizable_credential_canary_is_rejected(self):
        credential = "gh" + "p_" + "Z" * 36
        (self.root / "src/ForeverMouseoverBuff/Core.lua").write_text(credential)
        self.assert_rejected("SOURCE_PRIVATE_DATA")

    def test_version_mismatch_is_rejected(self):
        (self.root / "src/ForeverMouseoverBuff/ForeverMouseoverBuff.toc").write_text(
            self.toc.replace("0.7.0", "0.6.1")
        )
        self.assert_rejected("VERSION_MISMATCH")

    def test_unknown_manifest_file_is_rejected(self):
        (self.root / "src/ForeverMouseoverBuff/ForeverMouseoverBuff.toc").write_text(
            self.toc + "unreviewed.lua\n"
        )
        self.assert_rejected("TOC_INPUT_MISMATCH")

    def test_duplicate_manifest_entry_is_rejected(self):
        for name in ("ForeverMouseoverBuff.toc", "ForeverMouseoverBuff_Camelot.toc"):
            (self.root / "src/ForeverMouseoverBuff" / name).write_text(
                self.toc + "Core.lua\n"
            )
        self.assert_rejected("TOC_INPUT_MISMATCH")

    def test_archives_are_reproducible_and_assets_are_source_only(self):
        icon = self.root / "release/assets/project-icon.svg"
        icon.parent.mkdir(parents=True)
        icon.write_text("<svg/>\n")
        first = self.prepare()
        second_output = self.base / "second-release"
        second = release.prepare_release(self.root, second_output, "0.7.0")
        self.assertEqual(first, second)
        self.assertIn("release/assets/project-icon.svg", first["source_files"])
        self.assertNotIn("ForeverMouseoverBuff/project-icon.svg", first["addon_files"])
        for name in (
            "ForeverMouseoverBuff-0.7.0.zip",
            "ForeverMouseoverBuff-0.7.0-source.zip",
        ):
            self.assertEqual(
                (self.output / name).read_bytes(), (second_output / name).read_bytes()
            )

    def test_brand_assets_ship_in_source_and_never_addon_zip(self):
        names = (
            "brand-banner.svg",
            "brand-banner.png",
            "social-preview.svg",
            "social-preview.png",
            "how-it-works.svg",
            "how-it-works.png",
            "curseforge-banner.svg",
            "curseforge-banner.png",
        )
        folder = self.root / "release/assets"
        folder.mkdir(parents=True)
        for name in names:
            (folder / name).write_bytes(b"synthetic own brand asset")
        result = self.prepare()
        with zipfile.ZipFile(self.output / "ForeverMouseoverBuff-0.7.0.zip") as addon:
            for name in names:
                self.assertIn("release/assets/" + name, result["source_files"])
                self.assertNotIn("ForeverMouseoverBuff/" + name, addon.namelist())


class ReleaseWorkflowTests(unittest.TestCase):
    def test_ci_package_command_uses_current_manifest_version(self):
        # Validate both the checked-in workflow and its exported source template.
        # A fixed older --version makes an otherwise valid release fail in CI.
        project = Path(__file__).resolve().parents[1]
        toc = (
            project / "src/ForeverMouseoverBuff/ForeverMouseoverBuff.toc"
        ).read_text()
        version = next(
            line.split(":", 1)[1].strip()
            for line in toc.splitlines()
            if line.startswith("## Version:")
        )
        for name in (".github/workflows/ci.yml", "release/.github/workflows/ci.yml"):
            with self.subTest(workflow=name):
                self.assertIn(
                    f"--version {version} --output dist/ci-{version}",
                    (project / name).read_text(),
                    "CI packaging must validate the current manifest version.",
                )


if __name__ == "__main__":
    unittest.main()
