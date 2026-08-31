#!/usr/bin/env python3
"""Validate the binhost repository.

Checks:
  * config/packages.txt parses (no misformed atoms)
  * packages/ tree contains only .tbz2 binaries (no stray committed Packages)
  * the vendored ebuild overlay carries the three no-::gentoo atoms
    (sys-apps/bootc, app-shells/gum, dev-util/just) and repo glue
"""

from __future__ import annotations

import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r"^[-\w]+(?:/[-\w]+)$")
VENDORED_ATOMS = ("sys-apps/bootc", "app-shells/gum", "dev-util/just")


def parse_list(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def check_config() -> list[str]:
    errors = []
    config = ROOT / "config/packages.txt"
    if not config.is_file():
        return ["missing config/packages.txt"]
    for lineno, line in enumerate(config.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if not PATTERN.match(line):
            errors.append(f"config/packages.txt:{lineno}: malformed atom {line!r}")
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
        # Docs, placeholders, and staged binaries are fine; junk is not.
        if rel.endswith((".tbz2", ".gpkg.tar")) or rel in ("README.md", ".gitkeep"):
            continue
        errors.append(f"packages/ contains non-binpkg file: {rel}")
    return errors


def check_ebuilds_overlay() -> list[str]:
    errors = []
    ebuilds = ROOT / "ebuilds"
    if not ebuilds.is_dir():
        return ["missing ebuilds/ overlay"]
    if not (ebuilds / "metadata" / "layout.conf").is_file():
        errors.append("ebuilds/metadata/layout.conf missing")
    if not (ebuilds / "profiles" / "repo_name").is_file():
        errors.append("ebuilds/profiles/repo_name missing")
    else:
        repo_name = (ebuilds / "profiles" / "repo_name").read_text().strip()
        if repo_name != "gentoo-ing-ebuilds":
            errors.append(
                f"ebuilds/profiles/repo_name must be 'gentoo-ing-ebuilds' (portage "
                f"requires the repos.conf section name to match), got {repo_name!r}"
            )
    for atom in VENDORED_ATOMS:
        cat, pkg = atom.split("/")
        pkgs_with_ebuild = list((ebuilds / cat / pkg).glob("*.ebuild"))
        if not pkgs_with_ebuild:
            errors.append(f"ebuilds/{cat}/{pkg}: no .ebuild for {atom}")
    return errors


def main() -> None:
    errors = (
        check_config()
        + check_packages_tree()
        + check_ebuilds_overlay()
    )
    if errors:
        print("validation failed:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    n = sum(1 for p in (ROOT / "packages").rglob("*.tbz2"))
    count = len(parse_list(ROOT / "config/packages.txt"))
    print(f"OK: config parses; {count} atom(s) in the overlay set; ebuild overlay intact; {n} binpkg(s) staged in packages/")
    if n == 0:
        print("note: packages/ is empty; optional — `just seed` can stage official prebuilts.")


if __name__ == "__main__":
    main()