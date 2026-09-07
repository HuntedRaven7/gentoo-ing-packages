#!/usr/bin/env python3
"""Sync ebuilds/ into config/packages.txt and config/build-stages.txt.

Scans every .ebuild under ebuilds/, derives cat/pkg atoms, and ensures each
one appears in both config files.  New atoms are appended with a default
stage of 0 (safe fallback; stage ordering can be tuned later).

Modes:
  * default / --fix  : write missing entries back to disk
  * --check          : exit non-zero when drift is found (CI gate)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ATOM_RE = re.compile(r"^[-\w+]+/[-\w+]+$")
STAGE_RE = re.compile(r"^(\d+)\s+([-\w+]+/[-\w+]+)\s*$")
DEFAULT_STAGE = 0


def parse_packages(path: Path) -> tuple[list[str], set[str]]:
    lines = path.read_text().splitlines()
    atoms: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            atoms.append(line)
            continue
        if ATOM_RE.match(stripped):
            atoms.append(stripped)
        else:
            atoms.append(line)
    return atoms, {a for a in atoms if ATOM_RE.match(a)}


def parse_stages(path: Path) -> tuple[list[str], dict[str, int]]:
    lines = path.read_text().splitlines()
    stage_atoms: dict[str, int] = {}
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            out.append(line)
            continue
        m = STAGE_RE.match(stripped)
        if m:
            stage_atoms[m.group(2)] = int(m.group(1))
        out.append(stripped)
    return out, stage_atoms


def ebuild_atoms() -> set[str]:
    atoms: set[str] = set()
    for ebuild in (ROOT / "ebuilds").rglob("*.ebuild"):
        rel = ebuild.relative_to(ROOT / "ebuilds").as_posix()
        parts = rel.split("/")
        if len(parts) >= 2:
            atoms.add(f"{parts[0]}/{parts[1]}")
    return atoms


def append_package(atom: str, existing: list[str]) -> None:
    if existing and existing[-1].strip() != "":
        existing.append("")
    existing.append(atom)


def append_stage(atom: str, stage: int, existing: list[str]) -> None:
    if existing and existing[-1].strip() != "":
        existing.append("")
    existing.append(f"{stage}\t{atom}")


def sync(fix: bool) -> int:
    packages_path = ROOT / "config" / "packages.txt"
    stages_path = ROOT / "config" / "build-stages.txt"

    packages_lines, packages_set = parse_packages(packages_path)
    stages_lines, stages_map = parse_stages(stages_path)
    ebuilds = ebuild_atoms()

    missing_packages = sorted(ebuilds - packages_set)
    missing_stages = sorted(ebuilds - stages_map.keys())

    changed = False

    for atom in missing_packages:
        print(f"packages.txt: adding {atom}")
        append_package(atom, packages_lines)
        changed = True

    for atom in missing_stages:
        print(f"build-stages.txt: adding {atom} @ stage {DEFAULT_STAGE}")
        append_stage(atom, DEFAULT_STAGE, stages_lines)
        changed = True

    if not changed:
        print("OK: ebuilds/ is in sync with config/packages.txt and config/build-stages.txt")
        return 0

    if not fix:
        print("drift detected; re-run with --fix to apply")
        return 1

    packages_path.write_text("\n".join(packages_lines) + "\n")
    stages_path.write_text("\n".join(stages_lines) + "\n")
    print(f"updated: {len(missing_packages)} package(s), {len(missing_stages)} stage(s)")
    return 0


def main() -> None:
    fix = "--fix" in sys.argv
    if "--check" in sys.argv:
        fix = False
    code = sync(fix=fix)
    sys.exit(code)


if __name__ == "__main__":
    main()
