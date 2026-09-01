# Adding or updating a package in the binhost

The binhost serves the **entire** `gentoo-ing` set: the consumer image never
compiles anything and never talks to the official Gentoo binhost at runtime.
Everything it pins must exist as a binpkg here — either mirrored from the
official binhost or compiled in this factory.

One list drives the repo:

- `config/packages.txt` — the **full overlay set** that gets mirrored/compiled
  into binpkg each publish. It is a mirror of the `PACKAGES` array in the
  consumer's `gentoo-ing/build/10-build.sh` (plus `sys-kernel/installkernel`)
  and `tools/sync-check.py` fails CI if the two lists drift.

The rule that decides everything: **the overlay wins, and it is the only
binrepo the consumer configures** at `priority = 10000`. Anything staged here
or published replaces any prior version during `emerge --usepkgonly`.

## Case 1 — the official binhost carries the atom

The common case (systemd, ostree, podman, glib …). Add the atom to
`config/packages.txt`, and the next build **mirrors** the official prebuilt
binary (same profile, same USE) into the overlay. Nothing compiles; your only
job is keeping the list in parity with the consumer.

## Case 2 — `::gentoo` has an ebuild but the official binhost does not ship it

Kernel, firmware, skopeo, flatpak, iwd, jq, installkernel … the factory
**compiles** these in the `maker` stage (dependency binaries come as official
prebuilds) and publishes the binpkg.

1. Add the atom to `config/packages.txt`.
2. The next `just build` / CI run compiles it and emits the binpkg.
3. If the atom has dependency-visible USE overrides (like
   `sys-kernel/installkernel dracut`), declare them in
   `tools/make-binpkg.sh`'s `package.use` drop-in **and** on the consumer side,
   so `--binpkg-respect-use=y` matches.

## `--binpkg-respect-use=y` USE-gap conflicts (`package.use/respect-use`)

The strict `=y` resolution (same as the sealed consumer) refuses any official
binpkg whose USE flags diverge from this `desktop/gnome` profile — portage then
says "there are no ebuilds built with USE flags to satisfy" and can't always fall
back to a source build on its own. Examples:
GDM → `net-fs/samba` → `>=net-libs/ngtcp2-1.12.0[gnutls]` (official ngtcp2
binpkg ships `-gnutls`), and podman → `app-containers/containers-common` →
`net-firewall/iptables[nftables]` (official iptables binpkg ships `-nftables`).
Fix by forcing the flag in `tools/make-binpkg.sh`'s `package.use/respect-use`
drop-in so the maker compiles that atom from source to match (`--buildpkg` then
emits a binpkg with the required USE). Expect one of these per divergent atom
when bringing up a strict-`=y` set; each is a one-line `cat/pkg USE` entry.

## Case 3 — `::gentoo` has no ebuild at all

bootc, gum, and just work this way. Add a live ebuild under
`ebuilds/<category>/<pkg>/<pkg>-9999.ebuild` (root overlay glue lives in
`ebuilds/metadata/layout.conf` and `ebuilds/profiles/repo_name`; the ebuild is
exported to consumers so the atom resolves there too). Stable `KEYWORDS="amd64"`
keeps consumers on their stable-only diet.

## Case 4 — stage a ready-made .tbz2 (fast path)

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
`tools/make-binpkg.sh` — the compiled binaries themselves stay stable-visible
to consumers. Keep that special-casing to the toolchain atoms.

Those same toolchains are BDEPEND-only (the consumer seals itself to binpkgs
and never compiles, so it can never install them), so they are pruned from the
cache before publishing: `config/prune.txt` is the permanent never-ship list,
and `tools/prune-binhost.py` drops them alongside superseded versions. If a
toolchain ever needs to ship, delete its line from `config/prune.txt`, and keep
the list in sync with the `~amd64` keywords above.

## Update cycle (every 2 days)

A cron in `publish.yml` (`30 3 */2 * *`) rebuilds the binhost with a **fresh
portage tree** (`SYNC_PORTAGE=1`), so the full set tracks current stable
automatically. `emerge --buildpkg` only emits binpkg changes for what actually
moved; `tools/prune-binhost.py` then keeps just the newest version per package
and drops the never-ship toolchains, and a manifest diff against the published
image skips the push when nothing changed. You rarely need to bump a package by
hand — the cycle does it.

## After changes

```bash
just validate        # sanity-checks config, ebuild overlay, tree
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