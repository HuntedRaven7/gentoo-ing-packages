#!/usr/bin/env python3
"""Validate the binhost repository.

Checks:
  * config/packages.txt parses (no misformed patterns)
  * packages/ tree contains only .tbz2 binaries (no stray committed Packages)
  * no stale dotfiles/temp files that would pollute the image
"""

from __future__ import annotations

import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def check_config() -> list[str]:
    errors = []
    config = ROOT / "config/packages.txt"
    if not config.is_file():
        return ["missing config/packages.txt"]
    pattern = re.compile(r"^[-\w]+(?:/[-\w]+)$")
    for lineno, line in enumerate(config.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            line = line.split("=", 1)[1]
        if not pattern.match(line):
            errors.append(f"config/packages.txt:{lineno}: malformed pattern {line!r}")
    return errors


def check_packages_tree() -> list[str]:
    errors = []
    packages_dir = ROOT / "packages"
    if not packages_dir.is_dir():
        return ["missing packages/ directory"]
    for path in packages_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(packages_dir).as_posix()
        # Docs and placeholders are fine; committed binary junk is not.
        if rel.endswith(".tbz2") or rel in ("README.md", ".gitkeep"):
            continue
        errors.append(f"packages/ contains non-binpkg file: {rel}")
    return errors


def main() -> None:
    errors = check_config() + check_packages_tree()
    if errors:
        print("validation failed:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    n = sum(1 for p in (ROOT / "packages").rglob("*.tbz2"))
    print(f"OK: config parses; {n} binpkg(s) staged in packages/")
    if n == 0:
        print("note: overlay is empty; use `just seed` to pull the curated official set.")


if __name__ == "__main__":
    main()