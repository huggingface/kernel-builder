#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(prog="get_metadata")
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    # First pass: get package names.
    pkgs = set()
    for entry in args.directory.iterdir():
        if not entry.is_dir():
            continue
        pkgs.add(entry.name)

    # Second pass: get ROCm dependencies
    metadata = {}
    for entry in args.directory.iterdir():
        if not entry.is_dir():
            continue
        pkg = entry.name

        deps = set()

        depsFile = entry / "deps" / "deps.txt"
        if depsFile.exists():
            with open(depsFile) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 0:
                        continue
                    if parts[0] in pkgs:
                        deps.add(parts[0])

        metadata[pkg] = list(deps)

    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
