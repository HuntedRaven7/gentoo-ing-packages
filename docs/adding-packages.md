# Adding or updating a package in the binhost

The binhost is a curated overlay. Two sources feed `packages/`:

1. **Fresh binary builds** produced on this (or any Gentoo) machine, or
2. **Official binhost packages** pulled down with the seed tool, so the overlay
   starts from the same bytes upstream publishes.

The rule that decides everything: **the overlay wins**. `gentoo-ing` configures
`binrepos.conf` with this repo at `priority = 1` and the official Gentoo binhost
at `priority = 9959`, so a newer `gentoo-kernel-bin` dropped here replaces the
official one during `emerge --getbinpkg`.

## Option A — plop in an existing .tbz2 (fast)

```bash
# from another Gentoo machine / VM that emerged the package with buildpkg
scp user@host:/var/cache/binpkgs/sys-kernel/gentoo-kernel-bin-6.14_rc4_p1.tbz2 \
    packages/sys-kernel/
```

## Option B — seed from the official binhost

```bash
just seed                          # pulls config/packages.txt against x86-64/23.0
just seed "https://mirror.example/releases/amd64/binpackages/23.0/x86-64"
```

The seed tool downloads the newest matching `.tbz2` per configured package into
`packages/`, mirroring official index paths. Edit `config/packages.txt` to
expand the curated set, then `sed`-remove the line for anything you want the
official fallback to keep serving.

## Option C — build a custom one (e.g. custom USE flags, a patched ebuild)

On a Gentoo machine:

```bash
echo 'sys-kernel/gentoo-kernel-bin -firmware' >> /etc/portage/package.use/gentoo-ing
emerge --buildpkg sys-kernel/gentoo-kernel-bin
cp /var/cache/binpkgs/sys-kernel/gentoo-kernel-bin-*.tbz2 \
    "$REPO/packages/sys-kernel/"
```

## After changes

```bash
just validate        # sanity-checks the tree
git add packages && git commit -m "chore(binhost): add/update <pkg>"
git push
```

CI rebuilds the image and pushes `ghcr.io/HuntedRaven7/gentoo-ing-packages:latest`
(plus a `:gitsha` tag). The consumer image (`gentoo-ing`) picks it up on its
next build — the `COPY --from=...@sha256:...` pin is bumped and verified, then
the OS image is rebuilt and released through the normal `main` → `stable`
promotion.

**Never publish from a pull request.** PRs build and validate only; `:latest`
updates arrive exclusively from `main` pushes.