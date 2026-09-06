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
podman, skopeo, flatpak, flatpak deps, iwd, jq, gum, just, the full **GNOME
desktop** (`gnome-base/gnome`, GDM, NetworkManager), and everything else the
image lists. Both repos run the `default/linux/amd64/23.0/desktop/gnome/systemd`
profile so the maker's compiled closure exactly matches what the consumer's
strict `--binpkg-respect-use=y` will request.

Which atoms actually compile here:

- Atom the official binhost carries **with identical USE flags** (the base
  system packages it builds on the bare systemd profile that match this gnome
  profile — systemd, ostree, podman dependency tree, …) → **mirrored**: fetched
  as the official prebuilt binary, re-emitted into our overlay.
- Atom whose USE flags diverge from the official host **or** that the official
  host lacks (the desktop closure, bootc, kernel, firmware, installkernel,
  skopeo, flatpak, iwd, jq) → **compiled** here once per published image. The
  maker resolves with `--binpkg-respect-use=y` — the same strict policy as the
  consumer — so every binpkg it emits satisfies the consumer's USE match and
  nothing non-matching can brick the sealed build. Full GNOME (`gnome-base/gnome`)
  is mostly compiled for this reason.
- `sys-apps/bootc`, `app-shells/gum`, `dev-util/just` have no `::gentoo` ebuild
  at all; their live ebuilds live in `ebuilds/` and are exported for atom
  visibility.

Because `--buildpkg` emits a binpkg for every merged package (atoms *and* the
dependency closure), the overlay is fully self-contained.

This is a **personal binhost**: the compiled atoms are tuned for the owner's
machine (Ryzen 7 5800X, Zen 3) via `CFLAGS="-march=znver3"` in
`tools/make-binpkg.sh`. The factory sets an explicit `-march` (never
`-march=native` — the compile runs on GitHub runner hardware, so `native` would
target the runner's CPU, not the owner's). If the OS image ever has to run on
other hardware, relax that to the generic x86-64 default. Mirrored atoms (the
official prebuilt binaries) and `sys-kernel/gentoo-kernel-bin` ship with Gentoo's
generic flags.

## How it works

One workflow (`.github/workflows/build-matrix.yml`) drives the whole factory,
mirroring the utah-packages staged-matrix model:

- **bootstrap** bakes the shared **builder** image (`Containerfile` target
  `builder`: portage tree, profile, make.conf, ebuild overlay, official binhost
  trust via getuto, ccache) and pushes it to `:builder`. It is deterministic —
  ccache/distfiles are runtime mounts, never baked — so GitHub's BuildKit layer
  cache keeps hitting across runs and no job ever re-bootstraps portage.
- **prepare** computes the per-package matrices. `config/build-stages.txt`
  assigns every atom to a dependency-ordered stage (0–3): the GNOME stack rides
  on top of stage-0 foundations, gdm/control-center on top of gnome-shell, and
  so on. Push/schedule skip atoms the published `.manifest` already carries;
  a pull request builds exactly the ebuilds it touches.
- **stage0…stage3** run one parallel edge per atom on the builder image. Each
  edge mounts the shared **ccache/distfiles** caches (round-tripped between
  runs via the workflow cache, not per-package), and from stage 1 up all
  earlier stages' binpkgs as a local binrepo at `priority 10000` — outranking
  the official 9999 — so a compiled gap in the middle of the set (kernel, bootc,
  the desktop closure) is built *once* and reused, not recompiled per edge.
- **publish** (the compose) feeds every matrix artifact into the `maker` stage
  through the `binpkg-staging` build context, then `tools/make-binpkg.sh`
  mirrors the official prebuilds for atoms whose USE matches, runs
  `emerge --update --deep` over the set, quickpkgs the full closure, regenerates
  the `Packages` index (`emaint binhost --fix`, strict), and prunes. A byte-
  stable `.manifest` diff against the current publish skips the push when
  nothing changed; otherwise it pushes `:latest`, `:<sha>` and `:maker`, with
  build-provenance attestation.

Supporting pieces:

- `tools/bootstrap-env.sh` performs the one-time Portage setup the builder image
  bakes (tree sync, `default/linux/amd64/23.0/desktop/gnome/systemd` profile,
  make.conf, ebuild overlay, official binrepo + getuto, ccache). Toolchains
  (`rust-bin`, `go`, `go-bootstrap`) are accepted as `~amd64` for those atoms
  only.
- `tools/matrix-build.sh` runs the per-edge `emerge --update --deep --newuse
  <atom>` with the prior-stage binrepo and the shared caches, failing closed if
  no binpkg results.
- `tools/make-binpkg.sh` remains the compose step the published image is built
  from, and needs `distfiles-prime`/`ccache-prime`/`binpkg-staging` build
  contexts (see `Justfile` `build`).
- `packages/` still accepts plopped-in `.tbz2` files (optionally fetched via
  `just seed` from the official host once it starts carrying something) — they
  are staged before the builds and indexed afterwards.
- **Fail-closed:** the compose exits non-zero if the overlay cannot serve the
  full declared set (empty manifest, or any `config/packages.txt` atom absent
  from it), so a partial cache is never published to the sealed consumer.
- `main` publishes `ghcr.io/HuntedRaven7/gentoo-ing-packages:latest` plus a
  `:<sha>` tag. Pull requests build and validate only — never publish (a fork
  PR's edges rebuild the builder locally from the layer cache instead of the
  registry push).
- Consumers pin the image by digest (Renovate tracks the digest in the
  consuming `Containerfile`'s `FROM` line).

## Update cycle (every 2 days)

`build-matrix.yml` runs on a cron too (`30 3 */2 * *`) with `SYNC_PORTAGE=1`:
the builder image and the maker stage refresh the portage tree, the matrix does
`emerge --update --deep --newuse` over `config/packages.txt`, and the compose
re-mirrors/repackages only what actually moved, then prunes stale content. The prune policy keeps the cache intentionally small:

- one version per package (`tools/prune-binhost.py` deletes superseded builds),
- build-time-only toolchains never ship (`config/prune.txt` — the rust/go
  chain is BDEPEND-only, so a `--usepkgonly` consumer can never install it;
  dropping it removes gigabytes of dead weight).

A manifest-diff step (`tools/prune-binhost.py` writes a byte-stable
`.manifest` of the overlay) compares against the currently published image —
if no package version changed, the push is skipped entirely. The OCI image
stays bounded (one newest binpkg per package, not a growing pile of old
`.tbz2`s), and GH Actions only ever compiles what the official binhost
doesn't have.

`docker run` this image whenever you want "current stable binpkgs" — no touching
individual machines.

## HTTP binrepo (GitHub Pages)

A publish also mirrors the cache as a plain HTTP Gentoo binrepo on GitHub
Pages. Any stock Gentoo box can eat the bins without pulling a container:

```bash
echo 'PORTAGE_BINHOST="https://HuntedRaven7.github.io/gentoo-ing-packages/"' \
  >> /etc/portage/make.conf
emerge --getbinpkg --usepkgonly --oneshot <atom>
```

(The overlay carries the bootc/gum/just ebuilds only via the OCI image, so
`::gentoo`-absent atoms still need the consumer overlay; the HTTP mirror serves
the binpkg tree itself.) Enable it once in repo settings: **Settings → Pages →
Source → GitHub Actions**. Until then the deploy job reports its reason and
stays non-blocking.

## Security scanning (reports, not gates)

`security-scan` (a job in `build-matrix.yml`) runs **syft** (SBOM, attached as
an artifact) and **grype** (CVEs) against the published `:maker` image — the
stage that actually composed the set — and uploads the SARIF to GitHub **Code
Scanning**, so findings land on the repo's Security tab. `fail-build` is off:
findings never block a publish. The `:maker` tag is what makes this cheap — the
scan job pulls the already-built stage instead of recompiling.

## Usage

```bash
just validate            # sanity-checks config, ebuild overlay, tree
just show-package-set    # print the full overlay set the factory mirrors/builds
just build               # build the image locally (mirrors + compiles the set)
just prime-cache         # reuse the previous local build's ccache
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
4. If the atom's dependency closure must ride on earlier builds (GNOME stack,
   gdm, …), assign it a stage in `config/build-stages.txt` so the compile
   happens once and is reused by everything downstream.
5. Optional fast path: stage an official `.tbz2` into `packages/` (or a tbz2
   you produced on any Gentoo machine) to skip compiling that atom.
6. Open a PR (`just validate` first): CI builds exactly the atoms you changed.
   Merging to `main` runs the full matrix and publishes `:latest`; the next
   `gentoo-ing` build picks it up.

### Regenerating ebuilds with gentooit

Packages with a `.gentooit/<pkg>.yaml` config can have their ebuilds regenerated
with the [gentooit](https://github.com/HuntedRaven7/gentooit) tool:

```bash
just generate-build               # build the gentooit binary from submodule
just generate sys-apps/bootc      # regenerate a single package ebuild
just generate --all               # regenerate all ebuilds from .gentooit configs
```

The per-package yaml configs live under `.gentooit/` and drive source URL,
version pin, and metadata. The generated ebuild, `Manifest`, and `metadata.xml`
land in `ebuilds/<category>/<pkg>/`.

See [docs/adding-packages.md](docs/adding-packages.md) for the full walkthrough.

## Initial setup

1. Build once so a digest exists for `gentoo-ing` to pin:
   `just build && just push`
2. Copy the resulting digest into the `gentoo-ing` `Containerfile`:
   `podman inspect ghcr.io/HuntedRaven7/gentoo-ing-packages:latest --format '{{index .RepoDigests 0}}'`

The factory builds against the same `gentoo/stage3:systemd` base and
`x86-64`/`23.0` profile the consumer image uses.