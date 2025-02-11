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

    # Find -dev packages that should be merged.
    dev_to_merge = {}
    for pkg in pkgs:
        if pkg.endswith("-dev") and pkg[:-4] in pkgs:
            dev_to_merge[pkg] = pkg[:-4]

    # Second pass: get ROCm dependencies and merge -dev packages.
    metadata = {}

    # sorted will put -dev after non-dev packages.
    for pkg in sorted(pkgs):
        dir = args.directory / pkg

        # Gather dependencies.
        deps = set()
        depsFile = dir / "deps" / "deps.txt"
        if depsFile.exists():
            with open(depsFile) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 0:
                        continue
                    dep = parts[0]
                    if dep in pkgs:
                        dep = dev_to_merge.get(dep, dep)
                        deps.add(dep)

        if pkg in dev_to_merge:
            target_pkg = dev_to_merge[pkg]
            metadata[target_pkg]["components"].append(pkg)
            metadata[target_pkg]["deps"].update(deps)
        else:
            metadata[pkg] = {"components": [pkg], "deps": deps}

    # Remove self-references and convert dependencies to list.
    for name, pkg_metadata in metadata.items():
        deps = pkg_metadata["deps"]
        deps -= {name, f"name-dev"}
        pkg_metadata["deps"] = list(sorted(deps))

    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
