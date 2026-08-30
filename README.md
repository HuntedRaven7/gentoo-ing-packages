# gentoo-ing-packages

Curated Gentoo **binary package host (binhost)** for
[`gentoo-ing`](https://github.com/HuntedRaven7/gentoo-ing) — the "utah-packages"
of this factory.

It has one guarantee: **`gentoo-ing` never compiles a package.** Anything the
official Gentoo binhost does not ship is built *here* — in this GitHub Actions
build — and published as a ready-to-install binpkg. The consumer image installs
everything with `emerge --getbinpkg --usepkgonly`; a missing binpkg is a build
error, not a silent source build.

It publishes a data-only OCI image with two trees:

```
/var/cache/binhost/gentoo-ing          # binpkg tree + Packages index
/var/cache/binhost/gentoo-ing-ebuilds  # ebuild overlay (bootc, gum, just)
└── sys-apps/bootc/bootc-9999.ebuild
└── app-shells/gum/gum-9999.ebuild
└── dev-util/just/just-9999.ebuild
```

`gentoo-ing` consumes it with `COPY --from=` pinned by digest and configures it
in `binrepos.conf` at `priority = 10000`, just above the official Gentoo
binhost (`9999`). The official host still does the heavy lifting for the
long tail — most packages resolve straight from `distfiles.gentoo.org` as
prebuilt binaries, and it supplies the dependency binaries for the builds that
happen here.

## What gets built here

`config/gap-build.txt` lists the atoms the official host does not ship
(verified against its `Packages` index): `bootc`, the kernel + firmware,
`skopeo`, `flatpak`, `iwd`, `jq`, `gum`, `just`. Three of those —
`sys-apps/bootc`, `app-shells/gum`, `dev-util/just` — have no `::gentoo` ebuild
at all, so their live ebuilds live in `ebuilds/` in this repo and are exported
to consumers for atom visibility.

## How it works

- `tools/make-binpkg.sh` bootstraps Portage (tree, profile, `PKGDIR`), registers
  the vendored ebuild overlay + the official binhost as the dep source, then
  `emerge --buildpkg`es the gap closure. Toolchains (`rust-bin`, `go`,
  `go-bootstrap`) are accepted as `~amd64` for those atoms only.
- The `Containerfile` runs that script in a `maker` stage, regenerates the
  `Packages` index with `emaint binhost --fix` (strict: a corrupt tbz2 breaks
  the image), then publishes only the binhost tree + ebuild overlay to
  `scratch`.
- `packages/` still accepts plopped-in `.tbz2` files (optionally fetched via
  `just seed` from the official host once it starts carrying something) — they
  are staged before the builds and indexed afterwards.
- CI caches the emerge result per layer: an unchanged gap set is reused, so the
  factory only recompiles when a listed atom actually changes.
- `main` publishes `ghcr.io/HuntedRaven7/gentoo-ing-packages:latest` plus a
  `:gitsha` tag. Pull requests build and validate only — never publish.
- Consumers pin the image by digest (Renovate tracks the digest in the
  consuming `Containerfile`'s `FROM` line).

## Weekly update cycle

`publish.yml` runs on a cron too (`30 3 * * 0`, weekly) with `SYNC_PORTAGE=1`:
the maker stage refreshes the portage tree, runs `emerge --update --deep
--newuse` over `config/gap-build.txt`, repackages only what actually moved, and
prunes superseded versions. A manifest-diff step (`tools/prune-binhost.py`
writes a byte-stable `.manifest` of the overlay) compares against the currently
published image — if no package version changed, the push is skipped entirely.
The OCI image stays bounded (one newest binpkg per package, not a growing pile
of old `.tbz2`s), and GH Actions only ever compiles what the official binhost
doesn't have.

`docker run` this image whenever you want "current stable binpkgs" — no touching
individual machines.

## Security scanning (reports, not gates)

`security-scan` (part of `publish.yml`) runs **syft** (SBOM, attached as an
artifact) and **grype** (CVEs) against the `maker` image — the stage that
actually compiled the gap set — and uploads the SARIF to GitHub **Code
Scanning**, so findings land on the repo's Security tab. `fail-build` is off:
findings never block a publish. The `:maker` tag is what makes this cheap — the
scan job pulls the already-built stage instead of recompiling.

## Usage

```bash
just validate            # sanity-checks config, gap list, ebuild overlay, tree
just build               # build the image locally (compiles the gap closure)
just push                # push ghcr.io/HuntedRaven7/gentoo-ing-packages:latest
just show-gaps           # print the atoms the factory builds
just show-package-set    # print the curated overlay set
just seed                # stage official prebuilts into packages/ (optional)
```

## Adding a package

1. If `::gentoo` lacks its ebuild, add `ebuilds/<category>/<pkg>/` (see
   `ebuilds/sys-apps/bootc/` for a live-ebuild pattern).
2. Add the atom to `config/gap-build.txt` and `config/packages.txt`.
3. Optional fast path: stage an official `.tbz2` into `packages/` (or a tbz2
   you produced on any Gentoo machine) to skip compiling that atom.
4. `just validate`, commit, push.
5. CI rebuilds + publishes `:latest`. The next `gentoo-ing` build picks it up.

See [docs/adding-packages.md](docs/adding-packages.md) for the full walkthrough.

## Initial setup

1. Build once so a digest exists for `gentoo-ing` to pin:
   `just build && just push`
2. Copy the resulting digest into the `gentoo-ing` `Containerfile`:
   `podman inspect ghcr.io/HuntedRaven7/gentoo-ing-packages:latest --format '{{index .RepoDigests 0}}'`

The factory builds against the same `gentoo/stage3:systemd` base and
`x86-64`/`23.0` profile the consumer image uses.