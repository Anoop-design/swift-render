#!/usr/bin/env python3
"""Build a reproducible ZIP of the validated SwiftRender Codex plugin."""

import argparse
import hashlib
import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path

from validate import ValidationError, package_files, validate


def package(root, output):
    root = Path(root).resolve()
    output = Path(output).resolve()
    snapshot = [(path.relative_to(root).as_posix(), path.read_bytes()) for path in package_files(root)]
    metadata = validate(root)
    # Refuse output inside the plugin, including symlink-resolved paths. Otherwise
    # successive runs could accidentally capture a previous package.
    if output == root or root in output.parents:
        raise ValidationError("ZIP output must be outside the plugin directory")
    if output.suffix.lower() != ".zip":
        raise ValidationError("Output filename must end with .zip")
    entries = [(path.relative_to(root).as_posix(), path.read_bytes()) for path in package_files(root)]
    if entries != snapshot:
        raise ValidationError("Plugin files changed during validation; rerun packaging")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".plugin-", suffix=".zip", dir=output.parent, delete=False) as stream:
            temporary = Path(stream.name)
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for relative, data in entries:
                info = zipfile.ZipInfo(metadata["name"] + "/" + relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                # Helpers are invoked with python3; normalize permissions for
                # byte-identical builds independent of checkout umask or mtime.
                info.external_attr = (0o100644 << 16)
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        os.replace(temporary, output)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return {**metadata, "output": str(output), "bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = package(args.plugin, args.output)
    except (ValidationError, OSError, UnicodeError) as exc:
        print("Cannot package plugin: {}".format(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
