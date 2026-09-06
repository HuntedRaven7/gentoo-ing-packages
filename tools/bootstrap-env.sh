#!/usr/bin/env bash
set -euo pipefail

# Prepare a portage build environment: fresh tree, profile, make.conf, the
# vendored ebuild overlay, toolchain accept_keywords, USE-gap overrides, the
# official binhost as dependency source, binhost signature trust, and ccache.
#
# This is the SHARED environment setup for every build in the factory:
#   - the Containerfile `builder` stage runs it once so the whole matrix can
#     reuse the result as a (BuildKit-layer-cached) image instead of every job
#     re-doing emerge-webrsync + configuration;
#   - make-binpkg.sh calls it too, so the single-container `maker` build stays
#     identical for local `just build` and the compose step of the matrix.
#
# It must stay deterministic: nothing here depends on filesystem state that the
# workflow caches (ccache, distfiles), so the produced image layers are stable
# and the layer cache actually hits across runs.

BINHOST="/var/cache/binhost/gentoo-ing"
EBUILDS="/app/ebuilds"
OFFICIAL_BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/"
BRANCH_PROFILE="default/linux/amd64/23.0/desktop/gnome/systemd"

# 1. Portage tree. stage3 images ship a snapshot; SYNC_PORTAGE fetches a fresh
#    one for the scheduled (every 2 days) update cycle.
if [ ! -d /var/db/repos/gentoo/profiles ]; then
    emerge-webrsync || emerge --sync
elif [ "${SYNC_PORTAGE:-0}" = "1" ]; then
    emerge-webrsync || emerge --sync
fi

# 2. Profile
rm -f /etc/portage/make.profile
ln -s "/var/db/repos/gentoo/profiles/${BRANCH_PROFILE}" /etc/portage/make.profile

# 3. make.conf. Binpkg-respect-use=y (same as the consumer): the maker only
#    mirrors an official binary when its USE flags already match this profile's
#    (the gnome desktop profile the consumer also uses); everything whose USE
#    differs -- the bulk of the desktop closure the official host builds on the
#    bare systemd profile -- is compiled here. This GUARANTEES the emitted
#    binpkgs satisfy the consumer's strict --binpkg-respect-use=y, so a
#    non-matching mirrored binary can never slip into the overlay and brick the
#    sealed consumer build. --buildpkg emits every merged package into PKGDIR
#    (the overlay is then self-contained for the entire consumer set).
touch /etc/portage/make.conf
grep -q '^ACCEPT_LICENSE=' /etc/portage/make.conf \
    || echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
# This is a PERSONAL binhost -- the binaries are shipped to the owner's machine
# (Ryzen 7 5800X, Zen 3), never to generic consumer hardware. So the builder
# compiles with an explicit -march/-mtune for that CPU. NOTE: -march=native must
# NOT be used here, because the actual compile runs on GitHub Actions runner
# hardware inside a container, not on the target machine -- native would target
# the runner's CPU. Setting znver3 explicitly is what makes the produced binpkgs
# match the owner's silicon. If the OS image ever has to run on other hardware,
# relax this back to the generic x86-64 default.
grep -q '^CFLAGS=' /etc/portage/make.conf \
    || echo 'CFLAGS="-march=znver3 -O2 -pipe"' >> /etc/portage/make.conf
grep -q '^CXXFLAGS=' /etc/portage/make.conf \
    || echo 'CXXFLAGS="${CFLAGS}"' >> /etc/portage/make.conf
grep -q '^PKGDIR=' /etc/portage/make.conf \
    || echo "PKGDIR=${BINHOST}" >> /etc/portage/make.conf
grep -q '^FEATURES=.*getbinpkg' /etc/portage/make.conf \
    || echo 'FEATURES="-manifest getbinpkg binpkg-multi-instance parallel-fetch parallel-install ccache"' >> /etc/portage/make.conf
NPROC=$(nproc)
grep -q '^MAKEOPTS=' /etc/portage/make.conf \
    || echo "MAKEOPTS=\"-j${NPROC}\"" >> /etc/portage/make.conf
grep -q '^EMERGE_DEFAULT_OPTS=' /etc/portage/make.conf \
    || echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --buildpkg --binpkg-respect-use=y"' >> /etc/portage/make.conf
grep -q '^CCACHE_DIR=' /etc/portage/make.conf \
    || echo "CCACHE_DIR=/var/cache/ccache" >> /etc/portage/make.conf

# 4. Vendored ebuild overlay (the gentooit-generated live ebuilds, incl. the
#    three atoms ::gentoo has no ebuild for) so the full set resolves.
# The section name MUST equal the repo's internal name (profiles/repo_name).
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo-ing-ebuilds.conf <<EOF
[gentoo-ing-ebuilds]
location = ${EBUILDS}
priority = 80
EOF

# Toolchain atoms used to compile the gaps may trail the stable branch on
# amd64. Accept ~amd64 for THOSE ONLY, so the gap binaries themselves stay
# stable-visible to consumers (they only ever consume the finished binpkg).
# Bare atoms only: '=cat/pkg-*' ranges are invalid in package.accept_keywords.
#
# zig-bin 0.15 is the ::gentoo prebuilt Zig that ghostty (BDEPEND) compiles
# with; accepting ONLY zig-bin (not dev-lang/zig) keeps the factory from ever
# trying to build Zig from source (LLVM).
mkdir -p /etc/portage/package.accept_keywords
cat > /etc/portage/package.accept_keywords/toolchains <<EOF
dev-lang/rust-bin ~amd64
dev-lang/go ~amd64
dev-lang/go-bootstrap ~amd64
dev-lang/zig-bin ~amd64
EOF

# Vendored overlay atoms follow the gentooit convention of KEYWORDS="~amd64"
# (see .gentooit/*.yaml and ebuilds/). Accept EVERY ~amd64 overlay atom -- the
# ghostty pair, bootc/gum/just, wl-clipboard/tailscale, the skeleton pins, all
# of it -- so the factory's own pinned ebuilds resolve in the baked build
# environment. Auto-derived so a newly added ~amd64 atom cannot silently fail
# its matrix edge behind a "all ebuilds masked" emerge error. Consumers see the
# same ~amd64 atoms and must accept them too (gentoo-ing does).
cat > /etc/portage/package.accept_keywords/overlay <<EOF
$(find "${EBUILDS}" -name '*.ebuild' -print0 \
    | xargs -0 grep -l '^KEYWORDS=.*~amd64' \
    | while read -r ebuild; do
          rel="${ebuild#${EBUILDS}/}"
          cat="${rel%%/*}"
          pkg="${rel#${cat}/}"; pkg="${pkg%%/*}"
          echo "${cat}/${pkg} ~amd64"
      done | sort -u)
EOF

# ghostty builds with USE=wayland, which pins the system library
# gui-libs/gtk4-layer-shell (its DEPEND "--sysroot-lib-layershell" links the
# system lib, guaranteed via RDEPEND "gui-libs/gtk4-layer-shell:="). The atom
# is only ~amd64 in ::gentoo, so without acceptance every ghostty edge fails
# with "All ebuilds that could satisfy ... masked". Accept it in the factory
# (buildenv-only, so the ~amd64 layer shell binpkg is emitted into the overlay
# and consumers resolve it from there; gentoo-ing already mirrors overlay
# atoms as ~amd64).
mkdir -p /etc/portage/package.accept_keywords
cat > /etc/portage/package.accept_keywords/consumer-deps <<EOF
gui-libs/gtk4-layer-shell ~amd64
EOF

# gentoo-kernel-bin ships initramfs by default and requires an installkernel
# that can generate it (USE dracut), which the stable official binpkg lacks.
mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut
EOF

# --binpkg-respect-use=y USE-gap overrides. The strict =y resolution (same as
# the sealed consumer) refuses any official binpkg whose USE flags diverge from
# this (desktop/gnome) profile, and portage can't always fall back to a source
# build on its own. Forcing the flag here makes the build compile the atom from
# source to match (--buildpkg then emits a binpkg with the required USE).
#   - GDM -> net-fs/samba -> >=net-libs/ngtcp2-1.12.0[gnutls], but the official
#     ngtcp2 binpkg ships -gnutls.
#   - podman -> app-containers/containers-common -> net-firewall/iptables[nftables],
#     but the official iptables binpkg ships -nftables.
cat > /etc/portage/package.use/respect-use <<EOF
net-libs/ngtcp2 gnutls
net-firewall/iptables nftables
EOF

# 5. Official binhost supplies dependency binaries for the gap builds.
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoo.conf <<EOF
[gentoo]
priority = 9999
sync-uri = ${OFFICIAL_BINHOST}
verify-signature = false
location = /var/cache/binhost/gentoo
EOF

# 6. Trust the official binhost signature. Portage verifies official binpkgs
#    unconditionally in this version (unknown key = package unusable);
#    getuto is the supported trust helper for the release key. The later
#    emerge is the real gate: a signature failure still aborts the build.
getuto >/dev/null 2>&1 || true

# 7. ccache as the compile cache. Every gap compile (bootc, gum, just, kernel,
#    and the GNOME stack) is cached under /var/cache/ccache, mounted as a
#    runtime volume by the matrix jobs and round-tripped through the workflow
#    cache, so unchanged compiles reuse past results. ccache itself is
#    build-env-only (never shipped: it is in config/prune.txt). Portage's
#    FEATURES=ccache prepends /usr/lib/ccache/bin to the PATH; ccache installs
#    its own plain-name shims there, and we add the CHOST-prefixed names
#    portage/configure also invoke. ccache preserves the invocation name when
#    exec'ing the real compiler, so GCC keeps its g++/gcc language semantics in
#    configure probes (this is exactly what a bootstrap whose C++ checks all
#    failed was missing).
emerge --oneshot dev-util/ccache
mkdir -p /var/cache/ccache
mkdir -p /usr/lib/ccache/bin
ln -sf /usr/bin/ccache /usr/lib/ccache/bin/ccache
for target in x86_64-pc-linux-gnu-gcc x86_64-pc-linux-gnu-g++; do
    ln -sf /usr/bin/ccache "/usr/lib/ccache/bin/${target}"
done

# 7b. Break the glib build-time cycle (2026 tree).
#
# The current tree has a HARD dependency cycle between exactly the four
# packages that a fresh GLib build drags in as build-time Python tooling:
#
#     dev-libs/glib        ->(BDEPEND) dev-python/docutils
#     dev-python/docutils  ->(RDEPEND) dev-python/pillow
#     dev-python/pillow    ->(truetype) media-libs/harfbuzz
#     media-libs/harfbuzz  ->(glib) dev-libs/glib
#
# On a fresh stage3 none of the four is installed, so ANY emerge that has to
# build glib (which is every gnome-profile container build here) also has to
# merge docutils/pillow/harfbuzz in the SAME transaction — and portage cannot
# find an order, because the ring is real (each edge is mandatory). That is
# the "Error: circular dependencies: (dev-python/docutils...) depends on
# (dev-python/pillow...) depends on ... (dev-libs/glib...) (buildtime)" seen
# in every matrix edge of the first run.
#
# It is broken HERE, once, in the baked environment, by dropping
# harfbuzz[glib] for a single isolated bootstrap emerge: with that edge gone
# the four merge cleanly (harfbuzz(-glib) -> pillow -> docutils -> glib).
# The override is immediately removed and harfbuzz re-merged with its profile
# USE, so the baked image — and every binpkg it may emit — carries the correct
# flags. After this, every later -uDN (edges and the maker) finds all four
# already installed at current versions and never has to merge them alongside
# a fresh glib again.
#
# Cost is self-limiting: --update without --newuse merges only actual version
# bumps, and the final --newuse harfbuzz re-merge is a rebuild only on the run
# that actually flipped it, so a clean bake/publish is a no-op. --buildpkg-
# exclude keeps the temporary -glib harfbuzz bin (and the others' stale bins)
# out of PKGDIR; the compose's quickpkg pass re-emits docutils/pillow/harfbuzz/
# glib into the overlay with their final USE flags.
mkdir -p /etc/portage/package.use
echo 'media-libs/harfbuzz -glib' > /etc/portage/package.use/cycle-break
emerge --oneshot --update --buildpkg-exclude \
    'dev-libs/glib dev-python/docutils dev-python/pillow media-libs/harfbuzz' \
    dev-libs/glib dev-python/docutils dev-python/pillow media-libs/harfbuzz
rm -f /etc/portage/package.use/cycle-break
emerge --oneshot --newuse --buildpkg-exclude \
    'dev-libs/glib dev-python/docutils dev-python/pillow media-libs/harfbuzz' \
    media-libs/harfbuzz

echo "ENV: profile=${BRANCH_PROFILE}; make.conf, repos.conf, keywords, USE, binhost signature and ccache configured"
