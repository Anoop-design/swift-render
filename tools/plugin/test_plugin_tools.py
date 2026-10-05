"""Package integrity tests using an independent minimal plugin fixture."""

import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path

from package import package
from validate import SCHEMA, ValidationError, validate


class PluginToolsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "plugin"
        self.write("README.md", "# Test plugin\n\n[Skill](skills/example/SKILL.md)\n")
        self.write("LICENSE", "MIT fixture license\n")
        self.write("skills/example/SKILL.md", "---\nname: example\ndescription: Test an independent fixture.\n---\n\nRead [the guide](references/guide.md).\n")
        self.write("skills/example/references/guide.md", "# Guide\n\n[Website](https://example.com)\n")
        interface = {"displayName": "Example", "shortDescription": "Test this plugin"}
        identity = {"name": "example-plugin", "version": "0.1.0", "description": "Test fixture.", "license": "MIT"}
        self.write_json("plugin.json", {"$schema": SCHEMA, **identity, "extensions": {"com.openai": {"interface": interface}}})
        self.write_json(".codex-plugin/plugin.json", {**identity, "skills": "./skills/", "interface": interface})

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def write_json(self, relative, content):
        return self.write(relative, json.dumps(content))

    def change_manifest(self, relative, transform):
        path = self.root / relative
        data = json.loads(path.read_text())
        transform(data)
        self.write_json(relative, data)

    def test_valid_fixture_and_reproducible_zip_exclude_private_build_outputs(self):
        self.assertEqual(validate(self.root)["skills"], ["example"])
        # These are deliberately not runtime package inputs, even with private
        # data or executable bytes in them.
        self.write("skills/example/.build/private.txt", "/Users/person/project/secret")
        self.write("skills/example/__pycache__/module.pyc", "cache")
        self.write("skills/example/scripts/.env", "TOKEN=not-for-package")
        self.write("tests/test_fixture.py", "private test fixture")
        self.write(".git/config", "private remotes")
        self.write("unrelated.txt", "not allowlisted")
        first = package(self.root, self.base / "first.zip")
        for path in self.root.rglob("*"):
            os.utime(path, (1700000000, 1700000000))
        second = package(self.root, self.base / "second.zip")
        self.assertEqual(first["sha256"], second["sha256"])
        with zipfile.ZipFile(first["output"]) as archive:
            names = archive.namelist()
            self.assertEqual(len(names), 6)
            self.assertTrue(all(name.startswith("example-plugin/") for name in names))
            self.assertIn("example-plugin/.codex-plugin/plugin.json", names)
            self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))

    def test_manifest_identity_mismatch_fails(self):
        self.change_manifest(".codex-plugin/plugin.json", lambda data: data.update(version="0.2.0"))
        with self.assertRaisesRegex(ValidationError, "disagree on version"):
            validate(self.root)

    def test_interface_mismatch_fails(self):
        self.change_manifest(".codex-plugin/plugin.json", lambda data: data["interface"].update(displayName="Different"))
        with self.assertRaisesRegex(ValidationError, "interface metadata disagree"):
            validate(self.root)

    def test_manifest_escape_fails(self):
        for name in ("plugin.json", ".codex-plugin/plugin.json"):
            self.change_manifest(name, lambda data: (data.get("extensions", {}).get("com.openai", data))["interface"].update(logo="./../outside.png"))
        with self.assertRaisesRegex(ValidationError, "cannot contain"):
            validate(self.root)

    def test_missing_guide_fails(self):
        (self.root / "skills/example/references/guide.md").unlink()
        with self.assertRaisesRegex(ValidationError, "missing path"):
            validate(self.root)

    def test_link_outside_plugin_fails(self):
        (self.base / "private.md").write_text("private")
        self.write("README.md", "[Private](../private.md)\n")
        with self.assertRaisesRegex(ValidationError, "escapes the plugin root"):
            validate(self.root)

    def test_link_to_excluded_file_fails(self):
        self.write("tests/test.py", "test")
        self.write("README.md", "[Test](tests/test.py)\n")
        with self.assertRaisesRegex(ValidationError, "excluded from the ZIP"):
            validate(self.root)

    def test_missing_skill_description_fails(self):
        self.write("skills/example/SKILL.md", "---\nname: example\n---\nInstructions\n")
        with self.assertRaisesRegex(ValidationError, "needs a description"):
            validate(self.root)

    def test_private_path_fails(self):
        self.write("skills/example/references/guide.md", "Load /Users/person/private-app/Assets\n")
        with self.assertRaisesRegex(ValidationError, "Private machine path"):
            validate(self.root)

    def test_symlink_fails(self):
        (self.root / "assets").symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ValidationError, "Symlinks"):
            validate(self.root)

    def test_native_executable_fails(self):
        path = self.root / "skills/example/renderer"
        path.write_bytes(b"\xcf\xfa\xed\xfe" + bytes(40))
        with self.assertRaisesRegex(ValidationError, "Compiled executable"):
            validate(self.root)

    def test_output_inside_plugin_fails(self):
        with self.assertRaisesRegex(ValidationError, "outside the plugin"):
            package(self.root, self.root / "package.zip")

    def test_failed_validation_preserves_existing_output(self):
        output = self.base / "last-good.zip"
        output.write_bytes(b"previous accepted build")
        self.write("README.md", "[Broken](missing.md)\n")
        with self.assertRaises(ValidationError):
            package(self.root, output)
        self.assertEqual(output.read_bytes(), b"previous accepted build")


if __name__ == "__main__":
    unittest.main()
