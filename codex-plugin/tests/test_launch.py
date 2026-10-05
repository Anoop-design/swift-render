"""Run with: python3 -m unittest discover -s codex-plugin/tests -v"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "skills/app-launch-video/scripts/launch.py"
SPEC = importlib.util.spec_from_file_location("launch", SCRIPT)
launch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launch)


class LaunchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.app = self.base / "My App"
        self.app.mkdir()

    def put(self, name, content=b"example"):
        path = self.app / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def selection(self, names):
        path = self.base / "selection.json"
        path.write_text(json.dumps(names))
        return path

    def manifest(self, names):
        report = launch.snapshot(self.app, self.selection(names))
        path = self.base / "manifest.json"
        path.write_text(json.dumps(report))
        return path

    def test_spaces_and_change_detection(self):
        source = self.put("Views/Welcome Screen.swift", b"import SwiftUI\nstruct Welcome: View {}")
        manifest = self.manifest(["Views/Welcome Screen.swift"])
        self.assertTrue(launch.verify(self.app, manifest)["ok"])
        source.write_text("changed")
        self.assertEqual(launch.verify(self.app, manifest)["failures"][0]["reason"], "changed")
        source.unlink()
        self.assertFalse(launch.verify(self.app, manifest)["ok"])

    def test_path_escape_absolute_and_noncanonical(self):
        self.put("Safe.swift")
        for path in ["../outside.swift", str(self.app / "Safe.swift"), "a/../../Safe.swift", "./Safe.swift", "a//b", "a\\b"]:
            with self.subTest(path=path), self.assertRaises(launch.InputError):
                launch.safe_file(self.app, path)

    def test_symlink_files_and_directories(self):
        self.put("real/Source.swift")
        (self.app / "Link.swift").symlink_to(self.app / "real/Source.swift")
        (self.app / "linked").symlink_to(self.app / "real", target_is_directory=True)
        for name in ["Link.swift", "linked/Source.swift"]:
            with self.assertRaises(launch.InputError):
                launch.safe_file(self.app, name)
        inventory = launch.inspect_app(self.app, 100)
        self.assertEqual(inventory["coverage"]["symlinkEntries"], 2)
        self.assertEqual(len(inventory["files"]), 1)

    def test_inspection_hints_and_exclusions(self):
        self.put("Views/Home.swift", b"import SwiftUI\n@preconcurrency import RealityKit\nstruct Home: View { let time = Date(); }\n")
        self.put("Shaders/Glow.metal", b"#include <metal_stdlib>")
        self.put("Colors.xcassets/Accent.colorset/Contents.json", b"{}")
        for name in ["Pods/A.swift", ".build/B.swift", "Output/C.swift", "out/D.swift", ".env.swift", "secrets/key.swift", "private.key", "unrelated.xyz"]:
            self.put(name)
        report = launch.inspect_app(self.app, 100)
        self.assertEqual(len(report["files"]), 3)
        source = next(f for f in report["files"] if f["path"] == "Views/Home.swift")
        self.assertEqual(source["hints"]["imports"], ["RealityKit", "SwiftUI"])
        self.assertEqual(source["hints"]["viewCandidates"], ["Home"])
        self.assertIn("clock", source["hints"]["adaptationHints"])
        self.assertGreater(report["coverage"]["excludedEntries"], 0)

    def test_scan_limit_and_truncation(self):
        self.put("A.swift", b"a" * (launch.SOURCE_READ_LIMIT + 1))
        self.put("B.swift")
        report = launch.inspect_app(self.app, 1)
        self.assertTrue(report["coverage"]["limitReached"])
        self.assertTrue(report["files"][0]["hints"]["hintReadTruncated"])

    def test_verify_rejects_unsafe_manifest_and_duplicates(self):
        self.put("Safe.swift")
        manifest = self.manifest(["Safe.swift"])
        data = json.loads(manifest.read_text())
        data["files"][0]["path"] = "../Escape.swift"
        manifest.write_text(json.dumps(data))
        self.assertFalse(launch.verify(self.app, manifest)["ok"])
        with self.assertRaises(launch.InputError):
            launch.snapshot(self.app, self.selection(["Safe.swift", "Safe.swift"]))

    def test_report_cannot_modify_app_or_overwrite(self):
        with self.assertRaises(launch.InputError):
            launch.write_report(str(self.app / "report.json"), {}, self.app)
        output = self.base / "report.json"
        launch.write_report(str(output), {}, self.app)
        with self.assertRaises(launch.InputError):
            launch.write_report(str(output), {}, self.app)

    def test_init_success_existing_missing_and_unsafe_template(self):
        template = self.base / "template"
        template.mkdir()
        (template / "Package.swift").write_text("// template")
        (template / ".gitignore").write_text(".build/\n")
        target = self.base / "new film"
        result = launch.init_project(str(target), template)
        self.assertEqual(result["files"], [".gitignore", "Package.swift"])
        self.assertEqual((target / "Package.swift").read_text(), "// template")
        for directory, source in [(target, template), (self.base / "next", self.base / "missing")]:
            with self.assertRaises(launch.InputError):
                launch.init_project(str(directory), source)
        (template / "Bad.swift").symlink_to(template / "Package.swift")
        with self.assertRaises(launch.InputError):
            launch.init_project(str(self.base / "unsafe"), template)
        self.assertFalse((self.base / "unsafe").exists())


if __name__ == "__main__":
    unittest.main()
