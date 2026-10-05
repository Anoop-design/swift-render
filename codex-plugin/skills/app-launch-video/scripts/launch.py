#!/usr/bin/env python3
"""Local, read-only app discovery and provenance helpers for native launch films."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys

SCHEMA = 1
EXCLUDED_DIRS = {".git", ".build", ".swiftpm", "build", "deriveddata", "pods", "carthage",
                 "node_modules", "vendor", "dependencies", "checkouts", ".cache", "cache",
                 "caches", "out", "output", "outputs", "dist", "__pycache__"}
SENSITIVE_NAMES = {"credentials", "secrets", "tokens", "keychain", "googleservice-info.plist"}
SENSITIVE_SUFFIXES = {".pem", ".key", ".p12", ".p8", ".mobileprovision", ".keystore"}
KINDS = {
    "source": {".swift", ".metal", ".h", ".m", ".mm"},
    "project": {".pbxproj", ".xcconfig", ".xcscheme", ".xcworkspacedata"},
    "font": {".ttf", ".otf", ".woff", ".woff2"},
    "model": {".usdz", ".usd", ".usda", ".usdc", ".scn", ".obj", ".gltf", ".glb", ".bin"},
    "audio": {".wav", ".aif", ".aiff", ".mp3", ".m4a", ".caf", ".flac", ".ogg"},
    "artwork": {".png", ".jpg", ".jpeg", ".heic", ".webp", ".svg", ".pdf", ".hdr", ".exr", ".ktx"},
    "docs": {".md", ".markdown", ".rst"},
}
SOURCE_READ_LIMIT = 256 * 1024
DEFAULT_FILE_LIMIT = 10000
TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "NativeStarter"


class InputError(ValueError):
    pass


def sensitive(path: Path) -> bool:
    for part in path.parts:
        lower = part.lower()
        if lower.startswith(".env") or lower in SENSITIVE_NAMES or lower.startswith("service-account"):
            return True
        if Path(lower).suffix in SENSITIVE_SUFFIXES:
            return True
    return False


def excluded(path: Path) -> bool:
    return sensitive(path) or any(p.lower() in EXCLUDED_DIRS or p.startswith(".") for p in path.parts)


def root_path(value: str) -> Path:
    raw = Path(value).expanduser()
    if raw.is_symlink():
        raise InputError("The app root must be a real directory, not a symlink")
    root = raw.resolve(strict=True)
    if not root.is_dir():
        raise InputError("The app root must be a directory")
    return root


def safe_file(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or "\\" in name:
        raise InputError("Each selection must be a nonempty relative POSIX path")
    relative = PurePosixPath(name)
    if relative.is_absolute() or ".." in relative.parts or name != relative.as_posix():
        raise InputError(f"Unsafe or noncanonical relative path: {name!r}")
    if excluded(Path(name)):
        raise InputError(f"Excluded or sensitive path: {name!r}")
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise InputError(f"Symlinks are not read: {name!r}")
    if not current.is_file() or not current.resolve().is_relative_to(root):
        raise InputError(f"Missing or nonregular file: {name!r}")
    return current


def digest(path: Path) -> tuple[str, int]:
    hasher = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            hasher.update(chunk)
            size += len(chunk)
    return hasher.hexdigest(), size


def command(args: list[str]) -> dict:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=15, check=False)
        return {"ok": result.returncode == 0, "detail": (result.stdout or result.stderr).strip()[:1200]}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "detail": str(error)}


def git_head(root: Path) -> str | None:
    result = command(["git", "-C", str(root), "rev-parse", "HEAD"])
    value = result["detail"]
    return value if result["ok"] and re.fullmatch(r"[0-9a-f]{40,64}", value) else None


def kind_for(path: Path) -> str | None:
    if path.name == "Package.swift":
        return "project"
    if any(part.endswith(".xcassets") for part in path.parts):
        return "asset-catalog"
    for kind, suffixes in KINDS.items():
        if path.suffix.lower() in suffixes:
            return kind
    if path.name in {"Info.plist", "Package.resolved"}:
        return "project"
    if path.suffix.lower() == ".json" and any(part.lower() in {"assets", "resources"} for part in path.parts):
        return "resource-data"
    return None


def source_hints(path: Path) -> dict:
    with path.open("rb") as stream:
        sample = stream.read(SOURCE_READ_LIMIT + 1)
    truncated = len(sample) > SOURCE_READ_LIMIT
    text = sample[:SOURCE_READ_LIMIT].decode("utf-8", errors="replace")
    imports = sorted(set(re.findall(r"^\s*(?:@\w+\s+)?import\s+(?:struct\s+|class\s+|func\s+)?([\w.]+)", text, re.M)))
    views = sorted(set(re.findall(r"\b(?:struct|class)\s+(\w+)\s*:\s*(?:View|UIView|UIViewController|NSView|NSViewController)\b", text)))
    hints = {
        "animation": r"\b(?:withAnimation|animation|CAAnimation|CABasicAnimation|spring|keyframeAnimator|phaseAnimator)\b",
        "clock": r"\b(?:TimelineView|Date|Timer|CADisplayLink|CACurrentMediaTime|ContinuousClock|Task\.sleep)\b",
        "external-state": r"\b(?:HealthKit|HKHealthStore|CloudKit|CKContainer|URLSession|SwiftData|CoreData|UserDefaults|EnvironmentObject|ObservableObject)\b",
        "native-surface": r"\b(?:Metal|MTKView|RealityKit|ARKit|SceneKit|AVPlayer|UIViewRepresentable|NSViewRepresentable)\b",
        "asset-loading": r"\b(?:Image|UIImage|NSImage|Bundle|ModelEntity|TextureResource|Data)\s*\(",
    }
    return {"imports": imports, "viewCandidates": views,
            "adaptationHints": [name for name, pattern in hints.items() if re.search(pattern, text)],
            "hintReadTruncated": truncated}


def record(root: Path, name: str, hints: bool = False) -> dict:
    path = safe_file(root, name)
    sha, size = digest(path)
    result = {"path": name, "sha256": sha, "bytes": size, "kind": kind_for(Path(name)) or "selected"}
    if hints and path.suffix in {".swift", ".metal", ".m", ".mm", ".h"}:
        result["hints"] = source_hints(path)
    return result


def write_report(output: str, report: dict, root: Path | None = None) -> None:
    path = Path(output).expanduser()
    # Reports belong outside the app: even a new file would modify its checkout.
    if root is not None and path.resolve().is_relative_to(root):
        raise InputError("Write reports outside the app root to keep the app read-only")
    if path.exists() or path.is_symlink():
        raise InputError(f"Refusing to overwrite output: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def doctor() -> dict:
    checks = {}
    for name, args in {"xcodebuild": ["-version"], "swift": ["--version"], "git": ["--version"],
                       "ffmpeg": ["-version"], "ffprobe": ["-version"]}.items():
        executable = shutil.which(name)
        checks[name] = command([executable, *args]) if executable else {"ok": False, "detail": "Not found"}
        checks[name]["required"] = name in {"xcodebuild", "swift", "git"}
    ready = platform.system() == "Darwin" and all(c["ok"] for c in checks.values() if c["required"])
    return {"schemaVersion": SCHEMA, "ready": ready, "platform": platform.system(), "checks": checks,
            "note": "Detection only. GPU availability, SDK compatibility, signing, and actual builds remain unverified."}


def inspect_app(root: Path, limit: int) -> dict:
    files, packages, errors = [], [], []
    counters = {"visitedFiles": 0, "unclassifiedFiles": 0, "excludedEntries": 0, "symlinkEntries": 0}
    limited = False
    for directory, folders, names in os.walk(root, followlinks=False, onerror=lambda e: errors.append(str(e))):
        base = Path(directory)
        kept = []
        for name in sorted(folders):
            entry = base / name
            rel = entry.relative_to(root)
            if entry.is_symlink():
                counters["symlinkEntries"] += 1
            elif excluded(rel):
                counters["excludedEntries"] += 1
            else:
                kept.append(name)
                if entry.suffix in {".xcodeproj", ".xcworkspace", ".xcassets"}:
                    packages.append(rel.as_posix())
        folders[:] = kept
        for name in sorted(names):
            if counters["visitedFiles"] >= limit:
                limited = True
                break
            entry = base / name
            rel = entry.relative_to(root)
            counters["visitedFiles"] += 1
            if entry.is_symlink():
                counters["symlinkEntries"] += 1
            elif excluded(rel):
                counters["excludedEntries"] += 1
            elif kind_for(rel) is None:
                counters["unclassifiedFiles"] += 1
            else:
                try:
                    files.append(record(root, rel.as_posix(), hints=True))
                except (OSError, InputError) as error:
                    errors.append(f"{rel}: {error}")
        if limited:
            break
    counts = {kind: sum(f["kind"] == kind for f in files) for kind in sorted({f["kind"] for f in files})}
    return {"schemaVersion": SCHEMA, "type": "app-inventory", "gitHead": git_head(root),
            "packages": packages, "counts": counts, "files": files,
            "coverage": {**counters, "hashedFiles": len(files), "fileLimit": limit, "limitReached": limited,
                         "sourceHintReadBytes": SOURCE_READ_LIMIT, "errors": errors,
                         "excludedDirectoryNames": sorted(EXCLUDED_DIRS),
                         "notes": ["All hidden paths, recognized credential paths, and symlinks are skipped.",
                                   "Only recognized source, project, asset, and documentation files are hashed.",
                                   "Hints are textual heuristics, not a Swift parser or a complete dependency graph."]}}


def snapshot(root: Path, selection: Path) -> dict:
    names = json.loads(selection.read_text(encoding="utf-8"))
    if not isinstance(names, list) or not names or any(not isinstance(n, str) for n in names):
        raise InputError("Selection must be a nonempty JSON array of relative file paths")
    if len(names) != len(set(names)):
        raise InputError("Selection contains duplicate paths")
    return {"schemaVersion": SCHEMA, "type": "source-snapshot", "gitHead": git_head(root),
            "files": [record(root, name) for name in sorted(names)]}


def verify(root: Path, manifest: Path) -> dict:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schemaVersion") != SCHEMA or data.get("type") != "source-snapshot":
        raise InputError("Expected a source-snapshot manifest with schemaVersion 1")
    entries = data.get("files")
    if not isinstance(entries, list) or not entries:
        raise InputError("Manifest must contain a nonempty files array")
    failures, seen = [], set()
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise InputError("Invalid manifest entry")
        name = entry["path"]
        if name in seen or not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))):
            raise InputError("Duplicate path or invalid SHA256 in manifest")
        seen.add(name)
        try:
            current = record(root, name)
            if current["sha256"] != entry["sha256"] or current["bytes"] != entry.get("bytes"):
                failures.append({"path": name, "reason": "changed"})
        except (OSError, InputError) as error:
            failures.append({"path": name, "reason": str(error)})
    head = git_head(root)
    return {"ok": not failures, "checkedFiles": len(entries), "failures": failures,
            "gitHead": head, "snapshotGitHead": data.get("gitHead"),
            "gitHeadChanged": head != data.get("gitHead"),
            "note": "Selected content hashes determine success; a different Git HEAD is reported separately."}


def init_project(output: str, template: Path = TEMPLATE) -> dict:
    target = Path(output).expanduser()
    if target.exists() or target.is_symlink():
        raise InputError("The starter output directory must not already exist")
    if not template.is_dir() or template.is_symlink() or not (template / "Package.swift").is_file():
        raise InputError("Bundled NativeStarter template is missing")
    files = []
    for directory, folders, names in os.walk(template, followlinks=False):
        base = Path(directory)
        for name in folders + names:
            path = base / name
            permitted_dotfile = base == template and name == ".gitignore" and path.is_file()
            if path.is_symlink() or (name.startswith(".") and not permitted_dotfile) or name.lower() in EXCLUDED_DIRS:
                raise InputError(f"Unexpected template entry: {path.relative_to(template)}")
        for name in names:
            path = base / name
            permitted_rootfile = base == template and name in {".gitignore", "LICENSE"}
            if not path.is_file() or (not permitted_rootfile and path.suffix not in {".swift", ".metal", ".md", ".json", ".plist", ".txt"}):
                raise InputError(f"Unexpected template file: {path.relative_to(template)}")
            files.append(path.relative_to(template))
    target.mkdir(parents=True, exist_ok=False)
    for rel in files:
        destination = target / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template / rel, destination)
    return {"created": str(target.resolve()), "files": [p.as_posix() for p in sorted(files)],
            "note": "Copied only. No dependencies fetched and no build started."}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="Detect local build tools without installing anything")
    new = commands.add_parser("init", help="Copy the bundled native starter into a new directory")
    new.add_argument("--output", required=True)
    for name in ("inspect", "snapshot", "verify"):
        sub = commands.add_parser(name)
        sub.add_argument("--app", required=True)
        if name != "verify":
            sub.add_argument("--output", required=True)
        if name == "inspect":
            sub.add_argument("--max-files", type=int, default=DEFAULT_FILE_LIMIT)
        elif name == "snapshot":
            sub.add_argument("--selection", required=True)
        else:
            sub.add_argument("--manifest", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "doctor":
            report = doctor()
        elif args.command == "init":
            report = init_project(args.output)
        else:
            root = root_path(args.app)
            if args.command == "inspect":
                if args.max_files <= 0:
                    raise InputError("--max-files must be positive")
                report = inspect_app(root, args.max_files)
            elif args.command == "snapshot":
                report = snapshot(root, Path(args.selection))
            else:
                report = verify(root, Path(args.manifest))
            if args.command != "verify":
                write_report(args.output, report, root)
                report = {"output": args.output, "files": len(report["files"]), "type": report["type"]}
        print(json.dumps(report, indent=2))
        return 0 if report.get("ok", report.get("ready", True)) else 1
    except (OSError, InputError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
