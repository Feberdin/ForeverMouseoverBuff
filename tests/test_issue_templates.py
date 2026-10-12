"""Validate GitHub feedback forms and their addon prefill contract.

Input: checked-in YAML and linked project assets. Output: unittest diagnostics.
Invariants: optional technical fields, no private-data requirements, fixed repo links.
Debug: python3 -m unittest discover -s tests -p test_issue_templates.py -v
Dependency: PyYAML 6.0.3 is a development tool; it is not shipped in the addon.
"""

import re
import unittest
from pathlib import Path
from urllib.parse import urlparse

import yaml

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / ".github" / "ISSUE_TEMPLATE"
REPOSITORY = "https://github.com/Feberdin/ForeverMouseoverBuff"
RAW_PREFIX = "https://raw.githubusercontent.com/Feberdin/ForeverMouseoverBuff/main/"
FORMS = {
    "01-bug.yml": {"actual", "expected", "steps"},
    "02-wish.yml": {"workflow", "change"},
    "03-feature.yml": {"problem", "proposal", "value"},
}


def read_form(filename):
    """Use a real YAML parser so indentation/type errors fail with file context."""
    path = TEMPLATES / filename
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


class IssueTemplateTests(unittest.TestCase):
    """Documentation checks keep GitHub forms compatible with generated links."""

    def test_all_three_forms_have_valid_top_level_structure(self):
        names = []
        for filename in FORMS:
            with self.subTest(template=filename):
                form = read_form(filename)
                self.assertIsInstance(form, dict)
                self.assertEqual(
                    set(form), {"name", "description", "title", "labels", "body"}
                )
                for key in ("name", "description", "title"):
                    self.assertIsInstance(form[key], str)
                    self.assertTrue(form[key].strip())
                names.append(form["name"])
                self.assertIsInstance(form["labels"], list)
                self.assertTrue(form["labels"])
                self.assertTrue(all(isinstance(x, str) for x in form["labels"]))
                self.assertIsInstance(form["body"], list)
                self.assertTrue(form["body"])
        self.assertEqual(len(names), len(set(names)))

    def test_fields_use_documented_schema_and_unique_url_safe_ids(self):
        # Validate only field types we actually use; unsupported additions need review.
        allowed_attributes = {
            "textarea": {"label", "description", "placeholder", "render"},
            "dropdown": {"label", "description", "options"},
            "markdown": {"value"},
        }
        for filename in FORMS:
            with self.subTest(template=filename):
                ids = []
                for field in read_form(filename)["body"]:
                    self.assertIn(field["type"], allowed_attributes)
                    self.assertLessEqual(
                        set(field), {"type", "id", "attributes", "validations"}
                    )
                    attributes = field["attributes"]
                    self.assertIsInstance(attributes, dict)
                    self.assertLessEqual(
                        set(attributes), allowed_attributes[field["type"]]
                    )
                    if field["type"] == "markdown":
                        self.assertIsInstance(attributes["value"], str)
                        self.assertNotIn("id", field)
                        continue
                    self.assertRegex(field["id"], r"^[A-Za-z0-9_-]+$")
                    ids.append(field["id"])
                    self.assertIsInstance(attributes["label"], str)
                    self.assertTrue(attributes["label"].strip())
                    self.assertEqual(set(field["validations"]), {"required"})
                    self.assertIsInstance(field["validations"]["required"], bool)
                    if field["type"] == "dropdown":
                        options = attributes["options"]
                        self.assertIsInstance(options, list)
                        self.assertEqual(len(options), len(set(options)))
                        self.assertNotIn("None", options)
                self.assertEqual(len(ids), len(set(ids)))

    def test_environment_and_diagnostics_prefill_fields_are_optional_textareas(self):
        # These exact IDs are GitHub's URL-prefill keys used by the addon.
        for filename in FORMS:
            with self.subTest(template=filename):
                fields = {
                    field.get("id"): field for field in read_form(filename)["body"]
                }
                for field_id in ("environment", "diagnostics"):
                    field = fields[field_id]
                    self.assertEqual(field["type"], "textarea")
                    self.assertIs(field["validations"]["required"], False)
                    self.assertEqual(field["attributes"]["render"], "text")
                    self.assertNotIn("value", field["attributes"])

    def test_required_questions_capture_actionable_feedback_only(self):
        for filename, expected in FORMS.items():
            with self.subTest(template=filename):
                required = {
                    field["id"]
                    for field in read_form(filename)["body"]
                    if field.get("validations", {}).get("required")
                }
                self.assertEqual(required, expected)

    def test_forms_explain_publication_and_optional_technical_context(self):
        for filename in FORMS:
            with self.subTest(template=filename):
                copy = "\n".join(
                    field["attributes"]["value"]
                    for field in read_form(filename)["body"]
                    if field["type"] == "markdown"
                )
                for phrase in (
                    "GitHub-Konto",
                    "vor dem Absenden",
                    "Technische Angaben sind freiwillig",
                    "keine Spielernamen, Whisper, vollständigen SavedVariables",
                    "wird deine Meldung öffentlich",
                ):
                    self.assertIn(phrase, copy)

    def test_branded_images_reference_existing_project_assets(self):
        for filename in FORMS:
            with self.subTest(template=filename):
                intro = read_form(filename)["body"][0]["attributes"]["value"]
                images = re.findall(r'<img src="([^"]+)"', intro)
                self.assertEqual(len(images), 1)
                self.assertTrue(images[0].startswith(RAW_PREFIX))
                asset = images[0].removeprefix(RAW_PREFIX)
                self.assertEqual(asset, "release/assets/project-icon.png")
                self.assertTrue((ROOT / asset).is_file())

    def test_chooser_links_resolve_to_checked_in_project_documentation(self):
        config = read_form("config.yml")
        self.assertEqual(set(config), {"blank_issues_enabled", "contact_links"})
        self.assertIs(config["blank_issues_enabled"], False)
        self.assertEqual(len(config["contact_links"]), 3)
        for link in config["contact_links"]:
            with self.subTest(link=link["name"]):
                self.assertEqual(set(link), {"name", "url", "about"})
                prefix = REPOSITORY + "/blob/main/"
                self.assertTrue(link["url"].startswith(prefix))
                self.assertEqual(urlparse(link["url"]).scheme, "https")
                self.assertTrue((ROOT / link["url"].removeprefix(prefix)).is_file())
                self.assertTrue(link["name"].strip())
                self.assertTrue(link["about"].strip())

    def test_feedback_documentation_matches_form_names_and_data_boundary(self):
        documentation = (ROOT / "docs" / "feedback.md").read_text(encoding="utf-8")
        for filename in FORMS:
            self.assertIn(f"?template={filename}", documentation)
        self.assertIn("`environment`", documentation)
        self.assertIn("`diagnostics`", documentation)
        self.assertIn(
            "Beim Öffnen des vorbereiteten Links erhält GitHub bereits", documentation
        )
        self.assertIn("Ein öffentliches\nIssue entsteht erst", documentation)


if __name__ == "__main__":
    unittest.main()
