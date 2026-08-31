# gentoo-ing-packages

Gentoo **binary package host (binhost)** for
[`gentoo-ing`](https://github.com/HuntedRaven7/gentoo-ing) — the "utah-packages"
of this factory.

It has one guarantee: **`gentoo-ing` never compiles a package — and it never
talks to the official Gentoo binhost either.** This repo is the consumer's
*only* source of binaries. It mirrors the full official binhost set and
compiles every atom the official host does not ship, then publishes everything
as a ready-to-install binpkg tree. The consumer image installs with
`emerge --usepkgonly`; a missing binpkg is a build error, not a silent source
build.

It publishes a data-only OCI image with two trees:

```
/var/cache/binhost/gentoo-ing          # binpkg tree + Packages index
/var/cache/binhost/gentoo-ing-ebuilds  # ebuild overlay (bootc, gum, just)
└── sys-apps/bootc/bootc-9999.ebuild
└── app-shells/gum/gum-9999.ebuild
└── dev-util/just/just-9999.ebuild
```

`gentoo-ing` consumes it with `COPY --from=` pinned by digest and configures it
in `binrepos.conf` at `priority = 10000` — its sole binrepo. The official
binhost is used **only inside this factory build** (dependency binaries for the
compiled atoms, plus the mirrored set); the consumer never resolves from it.

## What gets built here

`config/packages.txt` is the **full gentoo-ing OS set** — a mirror of the
`PACKAGES` list in `gentoo-ing/build/10-build.sh` plus `sys-kernel/installkernel`
(a kernel dependency resolved with `USE=dracut`, which the official binhost
cannot serve). It covers bootc, kernel + firmware, systemd, dracut, ostree,
podman, skopeo, flatpak, flatpak deps, iwd, jq, gum, just, and everything else
the image lists.

Which atoms actually compile here:

- Atom the official binhost carries (systemd, ostree, podman, …)
  → **mirrored**: fetched as the official prebuilt binary, same USE/profile,
  re-emitted into our overlay. No wasteful recompiles.
- Atom the official binhost lacks (bootc, kernel, firmware, installkernel,
  skopeo, flatpak, iwd, jq) → **compiled** here once per published image.
- `sys-apps/bootc`, `app-shells/gum`, `dev-util/just` have no `::gentoo` ebuild
  at all; their live ebuilds live in `ebuilds/` and are exported for atom
  visibility.

Because `--buildpkg` emits a binpkg for every merged package (atoms *and* the
dependency closure), the overlay is fully self-contained.

## How it works

- `tools/make-binpkg.sh` bootstraps Portage (tree, profile, `PKGDIR`), registers
  the vendored ebuild overlay + the official binhost as the dep source, then
  `emerge --buildpkg`s the full set. Toolchains (`rust-bin`, `go`,
  `go-bootstrap`) are accepted as `~amd64` for those atoms only.
- The `Containerfile` runs that script in a `maker` stage, regenerates the
  `Packages` index with `emaint binhost --fix` (strict: a corrupt tbz2 breaks
  the image), then publishes only the binhost tree + ebuild overlay to
  `scratch`.
- `packages/` still accepts plopped-in `.tbz2` files (optionally fetched via
  `just seed` from the official host once it starts carrying something) — they
  are staged before the builds and indexed afterwards.
- CI caches the emerge result per layer: an unchanged set is reused, so the
  factory only recompiles when a listed atom actually changes.
- `main` publishes `ghcr.io/HuntedRaven7/gentoo-ing-packages:latest` plus a
  `:gitsha` tag. Pull requests build and validate only — never publish.
- Consumers pin the image by digest (Renovate tracks the digest in the
  consuming `Containerfile`'s `FROM` line).

## Update cycle (every 2 days)

`publish.yml` runs on a cron too (`30 3 */2 * *`) with `SYNC_PORTAGE=1`: the
maker stage refreshes the portage tree, runs `emerge --update --deep --newuse`
over `config/packages.txt`, re-mirrors/repackages only what actually moved, and
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
actually compiled the set — and uploads the SARIF to GitHub **Code
Scanning**, so findings land on the repo's Security tab. `fail-build` is off:
findings never block a publish. The `:maker` tag is what makes this cheap — the
scan job pulls the already-built stage instead of recompiling.

## Usage

```bash
just validate            # sanity-checks config, ebuild overlay, tree
just show-package-set    # print the full overlay set the factory mirrors/builds
just build               # build the image locally (mirrors + compiles the set)
just push                # push ghcr.io/HuntedRaven7/gentoo-ing-packages:latest
just seed                # stage official prebuilts into packages/ (optional)
```

`tools/sync-check.py` (run in CI) asserts `config/packages.txt` stays in parity
with the consumer's `build/10-build.sh` PACKAGES list — add an atom to one side
and the other must follow.

## Adding a package

1. Add the atom to the consumer's `gentoo-ing/build/10-build.sh` PACKAGES list.
2. Add the same atom to `config/packages.txt` here (sync-check enforces it).
3. If `::gentoo` lacks its ebuild, add `ebuilds/<category>/<pkg>/` (see
   `ebuilds/sys-apps/bootc/` for a live-ebuild pattern).
4. Optional fast path: stage an official `.tbz2` into `packages/` (or a tbz2
   you produced on any Gentoo machine) to skip compiling that atom.
5. `just validate`, commit, push. CI rebuilds + publishes `:latest`. The next
   `gentoo-ing` build picks it up.

See [docs/adding-packages.md](docs/adding-packages.md) for the full walkthrough.

## Initial setup

1. Build once so a digest exists for `gentoo-ing` to pin:
   `just build && just push`
2. Copy the resulting digest into the `gentoo-ing` `Containerfile`:
   `podman inspect ghcr.io/HuntedRaven7/gentoo-ing-packages:latest --format '{{index .RepoDigests 0}}'`

The factory builds against the same `gentoo/stage3:systemd` base and
`x86-64`/`23.0` profile the consumer image uses.