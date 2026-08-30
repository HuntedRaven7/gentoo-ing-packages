#!/usr/bin/env python3
"""Seed packages/ from the official Gentoo binhost.

Downloads the newest available .tbz2 for each package listed in
config/packages.txt into packages/, mirroring the official index layout so that
`emaint binhost --fix` produces a coherent `Packages` file at image build time.

Usage: seed-binhost.py [binhost-root-url]
"""

from __future__ import annotations

import gzip
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = "https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64"
UA = {"User-Agent": "gentoo-ing-packages-seed"}


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def load_index(root_url: str) -> str:
    try:
        return fetch(f"{root_url}/Packages").decode()
    except Exception:
        return gzip.decompress(fetch(f"{root_url}/Packages.gz")).decode()


def parse_index(text: str) -> list[dict[str, str]]:
    records = []
    for block in text.split("\n\n"):
        if not block.strip() or "__END_OF_PACKAGES_DB__" in block:
            continue
        fields = {}
        for line in block.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        records.append(fields)
    return records


def main() -> None:
    root_url = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ROOT
    patterns = [
        line.strip()
        for line in (ROOT / "config/packages.txt").read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    records = parse_index(load_index(root_url))

    for pattern in patterns:
        hits = [r for r in records if r.get("CPV", "").startswith(pattern)]
        if not hits:
            print(f"!! no binpkg found for {pattern}")
            continue
        best = max(hits, key=lambda r: r.get("BUILD_TIME", ""))
        path = best["PATH"]
        local = ROOT / "packages" / path
        local.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(
            urllib.request.Request(f"{root_url}/{path}", headers=UA)
        ) as resp, open(local, "wb") as out:
            out.write(resp.read())
        print(f"ok   {pattern:<12} -> {path}  ({best['CPV']})")


if __name__ == "__main__":
    main()