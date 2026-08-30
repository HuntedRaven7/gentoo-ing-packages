# Adding or updating a package in the binhost

The binhost is a curated overlay with a hard guarantee: **the consumer image
(`gentoo-ing`) never compiles anything.** Anything `::gentoo`'s official binhost
does not ship must be built *here* and published as a binpkg.

Two lists drive the repo:

- `config/gap-build.txt` — atoms the factory **builds to binpkg** each publish.
- `config/packages.txt` — the curated set the overlay guarantees (the atoms in
  `gap-build.txt` plus anything staged as a ready-made `.tbz2`), mirrored into
  `seed-binhost.py`'s fetch list.

The rule that decides everything: **the overlay wins**. `gentoo-ing` configures
`binrepos.conf` with this repo at `priority = 10000` and the official Gentoo
binhost at `priority = 9999`, so anything we publish replaces the official
version during `emerge --getbinpkg --usepkgonly`.

## Case 1 — `::gentoo` has an ebuild but the official binhost does not ship it

The common case (kernel, firmware, skopeo, flatpak, iwd, jq …).

1. Add the atom to `config/gap-build.txt` and `config/packages.txt`.
2. The next `just build` / CI run compiles it in the `maker` stage (deps come as
   binaries from the official host) and publishes the binpkg.

## Case 2 — `::gentoo` has no ebuild at all

bootc, gum, and just work this way. Add a live ebuild under
`ebuilds/<category>/<pkg>/<pkg>-9999.ebuild` (root overlay glue lives in
`ebuilds/metadata/layout.conf` and `ebuilds/profiles/repo_name`; the ebuild is
exported to consumers so the atom resolves there too). Stable `KEYWORDS="amd64"`
keeps consumers on their stable-only diet.

## Case 3 — stage a ready-made .tbz2 (fast path)

Skip the factory's compile by dropping an existing binary into `packages/`
(also pulls the newest official build for atoms the official host now carries):

```bash
# from another Gentoo machine / VM that emerged the package with buildpkg
scp user@host:/var/cache/binpkgs/sys-kernel/gentoo-kernel-bin-6.14_rc4_p1.tbz2 \
    packages/sys-kernel/
# ...or fetch the newest official tbz2 for an atom the official host carries
just seed
```

`tools/make-binpkg.sh` stages `packages/` into the overlay before building, so
staged binaries win and nothing gets recompiled unnecessarily.

## Adjusting toolchains

The factory compiles with prebuilt toolchains (`dev-lang/rust-bin`,
`dev-lang/go`, plus `dev-lang/go-bootstrap`) special-cased as `~amd64` in
`tools/make-binpkg.sh` — the gap binaries themselves stay stable-visible to
consumers. Keep that special-casing to the toolchain atoms.

## Weekly refresh (the update cycle)

A weekly cron in `publish.yml` rebuilds the binhost with a **fresh portage
tree** (`SYNC_PORTAGE=1`), so each gap atom (and its dependency closure) tracks
current stable automatically. `emerge --buildpkg` only emits binpkg changes for
what actually merged; `tools/prune-binhost.py` then keeps just the newest
version per package, and a manifest diff against the published image skips the
push when nothing moved. You rarely need to bump a package by hand — the
weekly cycle does it.

## After changes

```bash
just validate        # sanity-checks config, gap list, ebuild overlay, tree
git add config ebuilds packages && git commit -m "feat(binhost): add/update <pkg>"
git push
```

CI rebuilds (recompiling only atoms that changed) and pushes
`ghcr.io/HuntedRaven7/gentoo-ing-packages:latest` (plus a `:gitsha` tag). The
consumer image (`gentoo-ing`) picks it up on its next build — the
`COPY --from=...@sha256:...` pin is bumped and verified, then the OS image is
rebuilt and released through the normal `main` → `stable` promotion.

**Never publish from a pull request.** PRs build and validate only; `:latest`
updates arrive exclusively from `main` pushes.