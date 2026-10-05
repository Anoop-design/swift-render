#!/usr/bin/env python3
"""Validate this repository's local Codex plugin contract, without dependencies.

This checks package integrity, not every field in the remote Agent Plugins schema.
It deliberately never imports or executes bundled scripts.
"""

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit


SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
ROOT_FILES = {"plugin.json", "README.md", "CONTRIBUTING.md", "LICENSE", "NOTICE"}
ROOT_TREES = {"skills", "assets"}
EXCLUDED_PARTS = {
    ".git", ".build", ".swiftpm", "build", "out", "output", "node_modules",
    "__pycache__", ".venv", "venv", ".pytest_cache", ".mypy_cache", "tmp", "temp",
    "tests", ".ds_store",
}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".swp", ".swo", ".tmp", ".log"}
TEXT_SUFFIXES = {".md", ".json", ".yaml", ".yml", ".swift", ".metal", ".py", ".sh", ".txt", ".svg", ".toml", ".plist"}
PRIVATE_PATH = re.compile(r"(?:/Users/|/home/)[A-Za-z0-9_.-]+/|[A-Za-z]:[\\/]Users[\\/][A-Za-z0-9_.-]+[\\/]")
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
LINK = re.compile(r"!?\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+['\"][^)]*)?\s*\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+\]:\s*(<[^>]+>|\S+)", re.MULTILINE)


class ValidationError(ValueError):
    pass


def fail(message):
    raise ValidationError(message)


def is_included(relative):
    """Allow runtime package structure only, never an entire checkout."""
    parts = relative.parts
    if any(part.lower() in EXCLUDED_PARTS or part.endswith("~") for part in parts):
        return False
    if relative.suffix.lower() in EXCLUDED_SUFFIXES:
        return False
    if any(part.startswith(".env") for part in parts):
        return False
    if parts == (".codex-plugin", "plugin.json"):
        return True
    if len(parts) == 1:
        return relative.name in ROOT_FILES
    return parts[0] in ROOT_TREES


def package_files(root):
    root = Path(root).resolve()
    if not root.is_dir():
        fail("Plugin directory does not exist: {}".format(root))
    files = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if len(relative.parts) == 1 and relative.name in ROOT_TREES | {".codex-plugin"} and path.is_symlink():
            fail("Symlinks are not portable package inputs: {}".format(relative))
        if not is_included(relative):
            continue
        if path.is_symlink():
            fail("Symlinks are not portable package inputs: {}".format(relative))
        if path.is_file():
            files.append(path)
    return files


def load_json(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail("Cannot read JSON {}: {}".format(path.name, exc))
    if not isinstance(value, dict):
        fail("JSON root must be an object: {}".format(path.name))
    return value


def contained_path(root, base, value, label, included, manifest=False):
    if not isinstance(value, str) or not value:
        fail("{} must be a nonempty relative path".format(label))
    if manifest and not value.startswith("./"):
        fail("{} must start with ./".format(label))
    relative = PurePosixPath(value)
    if relative.is_absolute() or "\\" in value or re.match(r"^[A-Za-z]:", value):
        fail("{} must be a portable relative path".format(label))
    if manifest and ".." in relative.parts:
        fail("{} cannot contain ..".format(label))
    target = (base / value).resolve()
    try:
        target.relative_to(root)
    except ValueError:
        fail("{} escapes the plugin root".format(label))
    if not target.exists():
        fail("{} references a missing path: {}".format(label, value))
    if target.is_file() and target not in included:
        fail("{} references a file excluded from the ZIP: {}".format(label, value))
    if target.is_dir() and not any(target == p.parent or target in p.parents for p in included):
        fail("{} references a directory with no packaged files: {}".format(label, value))
    return target


def check_declared_paths(root, settings, included, label):
    for key in ("skills", "apps", "mcpServers"):
        if key in settings:
            value = settings[key]
            if not isinstance(value, str):
                fail("{} uses an unsupported {} declaration".format(label, key))
            contained_path(root, root, value, label + "." + key, included, manifest=True)
    interface = settings.get("interface", {})
    if not isinstance(interface, dict):
        fail(label + ".interface must be an object")
    for key in ("composerIcon", "logo", "logoDark"):
        if key in interface:
            contained_path(root, root, interface[key], label + ".interface." + key, included, manifest=True)
    screenshots = interface.get("screenshots", [])
    if not isinstance(screenshots, list):
        fail(label + ".interface.screenshots must be an array")
    for value in screenshots:
        contained_path(root, root, value, label + ".interface.screenshots", included, manifest=True)
    # This package intentionally does not ship hooks or MCP services. If added,
    # extend this validator and its allowlist together rather than silently omit them.
    for key in ("apps", "mcpServers", "hooks"):
        if key in settings:
            fail("{} requires explicit validation and packaging support for {}".format(label, key))


def check_skill(path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        fail("{} needs YAML frontmatter".format(path))
    try:
        end = lines.index("---", 1)
    except ValueError:
        fail("{} has unclosed frontmatter".format(path))
    fields = {}
    for line in lines[1:end]:
        match = re.match(r"^(name|description):\s*(.*)$", line)
        if match:
            key, value = match.groups()
            if key in fields:
                fail("{} has a duplicate {}".format(path, key))
            value = value.strip().strip("\"'")
            if not value or value in {">", "|", ">-", "|-"}:
                fail("{} requires a nonempty single-line {}".format(path, key))
            fields[key] = value
    if not NAME.fullmatch(fields.get("name", "")):
        fail("{} needs a kebab-case name".format(path))
    if fields["name"] != path.parent.name:
        fail("{} name does not match its skill directory".format(path))
    if not fields.get("description"):
        fail("{} needs a description".format(path))
    if not "\n".join(lines[end + 1:]).strip():
        fail("{} has no instructions".format(path))
    return fields["name"]


def check_links(root, path, text, included):
    # Ignore fenced samples: their placeholder paths are not package references.
    prose = re.sub(r"^\s*(```|~~~)[^\n]*\n.*?^\s*\1\s*$", "", text, flags=re.MULTILINE | re.DOTALL)
    for value in LINK.findall(prose) + REFERENCE_LINK.findall(prose):
        value = value.strip("<>")
        url = urlsplit(value)
        if url.scheme or url.netloc or not url.path:
            continue
        contained_path(root, path.parent, unquote(url.path), str(path.relative_to(root)) + " link", included)


def validate(root):
    root = Path(root).resolve()
    files = package_files(root)
    included = set(files)
    for required in ("plugin.json", ".codex-plugin/plugin.json", "README.md", "LICENSE"):
        if root / required not in included:
            fail("Required package file is missing: {}".format(required))
    portable = load_json(root / "plugin.json")
    compatibility = load_json(root / ".codex-plugin" / "plugin.json")
    if portable.get("$schema") != SCHEMA:
        fail("plugin.json must declare the Agent Plugins 1.0.0 schema")
    if not NAME.fullmatch(portable.get("name", "")):
        fail("Plugin name must use kebab-case")
    if not VERSION.fullmatch(portable.get("version", "")):
        fail("Plugin version must be a semantic version")
    if not isinstance(portable.get("description"), str) or not portable["description"].strip():
        fail("Plugin description is required")
    for key in ("name", "version", "description", "author", "repository", "license"):
        if portable.get(key) != compatibility.get(key):
            fail("Portable and compatibility manifests disagree on {}".format(key))
    extensions = portable.get("extensions", {})
    if not isinstance(extensions, dict) or not isinstance(extensions.get("com.openai"), dict):
        fail("Portable manifest needs extensions.com.openai metadata")
    settings = extensions["com.openai"]
    if settings.get("interface") != compatibility.get("interface"):
        fail("Portable and compatibility interface metadata disagree")
    if compatibility.get("skills") != "./skills/":
        fail("Compatibility manifest must declare skills: ./skills/")
    check_declared_paths(root, settings, included, "extensions.com.openai")
    check_declared_paths(root, compatibility, included, "compatibility")
    if (root / "mcp.json").exists() or (root / ".mcp.json").exists():
        fail("MCP configuration requires explicit packaging support")
    skill_paths = sorted((root / "skills").glob("*/SKILL.md"))
    if not skill_paths:
        fail("Package must include at least one skills/<name>/SKILL.md")
    skill_names = [check_skill(path) for path in skill_paths]
    for path in files:
        raw = path.read_bytes()
        if raw[:4] in {b"\x7fELF", b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"} or raw[:2] == b"MZ":
            fail("Compiled executable must not be packaged: {}".format(path.relative_to(root)))
        if path.suffix.lower() in TEXT_SUFFIXES or path.name in ROOT_FILES:
            try:
                text = raw.decode("utf-8")
            except UnicodeError:
                fail("Expected UTF-8 text: {}".format(path.relative_to(root)))
            if PRIVATE_PATH.search(text):
                fail("Private machine path in {}".format(path.relative_to(root)))
            if path.suffix.lower() == ".md":
                check_links(root, path, text, included)
            if path.name == "openai.yaml":
                for key, value in re.findall(r"^\s*(icon_small|icon_large):\s*[\"']?([^\"'\n]+)[\"']?\s*$", text, re.MULTILINE):
                    contained_path(root, path.parent.parent, value.strip(), str(path.relative_to(root)) + " " + key, included)
    return {"name": portable["name"], "version": portable["version"], "skills": skill_names, "files": len(files)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.plugin)
    except (ValidationError, OSError, UnicodeError) as exc:
        print("Invalid plugin: {}".format(exc), file=sys.stderr)
        return 1
    print(json.dumps({"valid": True, **result}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
