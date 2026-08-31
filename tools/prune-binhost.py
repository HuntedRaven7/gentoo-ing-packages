#!/usr/bin/env python3
"""Prune the binhost overlay and emit a manifest.

Keeps only the newest version of each package in the overlay (so the published
OCI image stays bounded — one binpkg per package, not a growing stack of
superseded tbz2s), drops packages listed in a "never ship" build-time-only
list, and writes a sorted `.manifest` of what the overlay currently
guarantees. The publish workflow diffs that manifest against the previously
published image to skip no-op pushes.

The manifest is stable in content: identical runs produce byte-identical
manifests, which is what makes the "nothing changed, don't push" gate work.

Usage: prune-binhost.py [--binhost DIR] [--manifest FILE] [--prune-list FILE]
                        [--dry-run]
"""

from __future__ import annotations

import argparse
import re
import sys
from functools import cmp_to_key
from pathlib import Path

try:
    from portage.versions import vercmp as _raw_vercmp

    def vercmp(a: str, b: str) -> int:
        result = _raw_vercmp(a, b)
        if result is not None:
            return result
        return (a > b) - (a < b)

except ImportError:  # local/dev fallback (image always has portage)
    def vercmp(a: str, b: str) -> int:
        return (a > b) - (a < b)


FILE_RE = re.compile(r"^(?P<name>.+?)-(?P<ver>\d.*)\.(?P<ext>tbz2|gpkg\.tar)$")


def parse_file(rel: str) -> tuple[str, str] | None:
    """Return (group, version) for an overlay file path or None.

    The group is the top-level category (safe across the flat and the
    binpkg-multi-instance nested layout); the version starts at the '-' that
    precedes the first digit in the package filename.
    """
    parts = rel.split("/")
    leaf = parts[-1]
    m = FILE_RE.match(leaf)
    if not m:
        return None
    group = parts[0]
    return f"{group}/{m.group('name')}", m.group("ver")


def load_prune_list(path: Path) -> set[str]:
    """Category/package entries that must never ship to consumers.

    These are build-time-only (BDEPEND) toolchains that the consumer — a
    sealed --usepkgonly system that never compiles — can never install. They
    enter the overlay because --buildpkg re-emits everything the maker emits,
    so they are dropped here before the index and image are produced.
    """
    if path is None or not path.is_file():
        return set()
    return {
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binhost", default="/var/cache/binhost/gentoo-ing")
    parser.add_argument("--manifest", default=None, help="defaults to <binhost>/.manifest")
    parser.add_argument(
        "--prune-list",
        default=None,
        metavar="FILE",
        help="permanent never-ship category/package atoms (default: none)",
    )
    parser.add_argument("--dry-run", action="store_true", help="report only, delete nothing")
    args = parser.parse_args()

    host = Path(args.binhost)
    manifest = Path(args.manifest) if args.manifest else host / ".manifest"
    prune_list = load_prune_list(Path(args.prune_list) if args.prune_list else None)

    buckets: dict[str, list[tuple[str, str, Path]]] = {}
    for path in host.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(host).as_posix()
        if not (rel.endswith(".tbz2") or rel.endswith(".gpkg.tar")):
            continue
        parsed = parse_file(rel)
        if not parsed:
            print(f"!! unparseable binpkg filename: {rel}")
            continue
        group, version = parsed
        buckets.setdefault(group, []).append((version, rel, path))

    removed: list[str] = []
    kept: list[str] = []
    for group in sorted(buckets):
        if group in prune_list:
            for version, rel, path in buckets[group]:
                print(f"- {rel} (never-ship: build-time-only toolchain)")
                removed.append(rel)
                if not args.dry_run:
                    path.unlink()
            continue
        entries = sorted(
            buckets[group],
            key=cmp_to_key(lambda a, b: vercmp(a[0], b[0])),
            reverse=True,
        )
        best = entries[0]
        kept.append(f"{group}-{best[0]}")
        for version, rel, path in entries[1:]:
            print(f"- {rel} (superseded by {best[0]})")
            removed.append(rel)
            if not args.dry_run:
                path.unlink()

    if not args.dry_run:
        manifest.write_text("\n".join(sorted(kept)) + "\n")

    print(f"kept {len(kept)} binpkg(s)")
    if removed:
        print(f"pruned {len(removed)} binpkg(s) (superseded versions or never-ship toolchains)")
        print("overlay is NOT a no-op: content changed")
    else:
        print("no pruned binpkg(s); manifest unchanged if versions did not move")

    if args.dry_run:
        print("dry-run: nothing deleted")


if __name__ == "__main__":
    main()