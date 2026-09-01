#!/usr/bin/env python3
"""Assert config/packages.txt <=> gentoo-ing/build/10-build.sh PACKAGES parity.

The gentoo-ing-packages repo is the consumer's base binrepo: it must carry
every atom gentoo-ing asks for (except the module overlay's), or the
consumer's --usepkgonly build fails. This script fails the build when drift
goes either way:

  * an atom added to gentoo-ing build/10-build.sh but missing here
    (consumer would hard-fail at image build time)
  * an atom present here but not requested by the consumer
    (dead cargo bloat in the overlay)

Two atoms are exempt, each in the opposite direction:

  * sys-kernel/installkernel (FORCED) is required in the build set regardless:
    the consumer resolves it WITH USE=dracut and the official binhost ships no
    installkernel binpkg, so it must be compiled here in the factory (it also
    prunes out of the akmods overlay).
  * x11-drivers/nvidia-drivers (EXTERNAL) is requested by the consumer but
    must NOT be built here: it is the out-of-tree kernel module, shipped from
    the gentoo-ing-akmods module overlay (built against the consumer's exact
    kernel). Compiling it in this repo would target the wrong kernel.

Usage: tools/sync-check.py [consumer 10-build.sh URL]
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSUMER_LIST_URL = (
    "https://raw.githubusercontent.com/HuntedRaven7/gentoo-ing/main/build/10-build.sh"
)
FORCED = {"sys-kernel/installkernel"}
EXTERNAL = {"x11-drivers/nvidia-drivers"}

ARRAY = re.compile(r"PACKAGES=\((.*?)\)", re.DOTALL)
ATOM = re.compile(r"^\s*([-\w]+/[-\w]+)\s*$")


def parse_list(path: Path) -> set[str]:
    return {
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    }


def fetch_consumer_atoms(url: str) -> set[str]:
    with urllib.request.urlopen(url, timeout=30) as resp:
        text = resp.read().decode()
    match = ARRAY.search(text)
    if not match:
        raise SystemExit(f"ERROR: could not find PACKAGES=(...) in {url}")
    return {m.group(1) for line in match.group(1).splitlines() if (m := ATOM.match(line))}


def main() -> None:
    overlay = parse_list(ROOT / "config/packages.txt")
    url = sys.argv[1] if len(sys.argv) > 1 else CONSUMER_LIST_URL
    consumer = fetch_consumer_atoms(url)
    expected = (consumer - EXTERNAL) | FORCED

    missing = sorted(expected - overlay)
    extra = sorted(overlay - expected)

    if not missing and not extra:
        n = len(overlay)
        print(f"OK: config/packages.txt matches gentoo-ing PACKAGES "
              f"(+{sorted(FORCED)}, -{sorted(EXTERNAL)}); {n} atom(s)")
        return

    if missing:
        print(f"ERROR: consumer atom(s) missing from config/packages.txt: {missing}")
    if extra:
        print(f"ERROR: atom(s) in config/packages.txt not requested by consumer: {extra}")
    sys.exit(1)


if __name__ == "__main__":
    main()