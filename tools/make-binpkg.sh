#!/usr/bin/env bash
set -euo pipefail

# Build the gentoo-ing binhost overlay: compile or mirror the FULL consumer
# package set (config/packages.txt — same list as gentoo-ing/build/10-build.sh)
# and publish it as a self-contained binpkg tree, plus export the vendored
# ebuild overlay for consumer atom visibility.
#
# Designed to run on every publish AND on the scheduled update cycle
# (SYNC_PORTAGE=1):
#   - a fresh tree sync makes -uDN discover version bumps
#   - --getbinpkg mirrors official binaries for atoms the official host already
#     carries (no wasteful recompiles); atoms it does not ship are compiled here
#   - --buildpkg emits a binpkg for every merged package (atoms AND dependency
#     closure), so the overlay is the consumer's only source
#   - unchanged packages are not re-packaged, so unchanged runs are cheap + cached
#   - prune-binhost.py keeps only the newest version per package, so the published
#     image stays bounded (no stacked superseded tbz2s)
#   - .manifest is the byte-stable summary the workflow diffs to skip no-op pushes

BINHOST="/var/cache/binhost/gentoo-ing"
EBUILDS="/app/ebuilds"
EBUILDS_EXPORT="/var/cache/binhost/gentoo-ing-ebuilds"
OFFICIAL_BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/"
BRANCH_PROFILE="default/linux/amd64/23.0/systemd"

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

# 3. make.conf. Binpkg-respect-use=n: mirrored official binaries keep their
#    official USE flags, and only atoms the official host truly lacks are
#    compiled. --buildpkg emits every merged package into PKGDIR (the overlay
#    is then self-contained for the entire consumer set).
touch /etc/portage/make.conf
grep -q '^ACCEPT_LICENSE=' /etc/portage/make.conf \
    || echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
grep -q '^PKGDIR=' /etc/portage/make.conf \
    || echo "PKGDIR=${BINHOST}" >> /etc/portage/make.conf
grep -q '^FEATURES=.*getbinpkg' /etc/portage/make.conf \
    || echo 'FEATURES="-manifest getbinpkg binpkg-multi-instance parallel-fetch parallel-install"' >> /etc/portage/make.conf
NPROC=$(nproc)
grep -q '^MAKEOPTS=' /etc/portage/make.conf \
    || echo "MAKEOPTS=\"-j${NPROC}\"" >> /etc/portage/make.conf
grep -q '^EMERGE_DEFAULT_OPTS=' /etc/portage/make.conf \
    || echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --buildpkg --binpkg-respect-use=n"' >> /etc/portage/make.conf

# 4. Vendored ebuild overlay (bootc, gum, just) so the full set resolves.
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
mkdir -p /etc/portage/package.accept_keywords
cat > /etc/portage/package.accept_keywords/toolchains <<EOF
dev-lang/rust-bin ~amd64
dev-lang/go ~amd64
dev-lang/go-bootstrap ~amd64
EOF

# gentoo-kernel-bin ships initramfs by default and requires an installkernel
# that can generate it (USE dracut), which the stable official binpkg lacks.
mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut
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

# 7. Stage any plopped-in .tbz2 first (faster prebuilt starting points).
mkdir -p "${BINHOST}"
if find /app/packages -name '*.tbz2' -o -name '*.gpkg.tar' | grep -q .; then
    cp -avf /app/packages/. "${BINHOST}/"
fi

# 8. Build the full overlay set. --getbinpkg mirrors official binaries where
#    the official host already carries an atom (same profile, same USE); only
#    atoms it lacks actually compile. --buildpkg re-emits every merged package
#    (closure included), making the overlay the consumer's sole binrepo.
mapfile -t BUILD_SET < <(sed -e '/^#/d' -e '/^[[:space:]]*$/d' /app/config/packages.txt)
if [ "${#BUILD_SET[@]}" -gt 0 ]; then
    emerge --update --deep --newuse "${BUILD_SET[@]}"
fi

# 9. Regenerate the Packages index. Strict: a corrupt tbz2 fails the image.
emaint binhost --fix

# 10. Prune superseded versions (bounds the image) and re-index.
python3 /app/tools/prune-binhost.py --binhost "${BINHOST}"
emaint binhost --fix

# 11. Export the ebuild overlay for consumers (atom visibility for bootc/gum/just).
mkdir -p "${EBUILDS_EXPORT}"
cp -avf "${EBUILDS}/." "${EBUILDS_EXPORT}/"

# 12. Report
count=$(find "${BINHOST}" -name '*.tbz2' -o -name '*.gpkg.tar' | wc -l)
echo "OVERLAY: ${count} binpkg(s) in ${BINHOST}"
echo "EBUILDS: exported to ${EBUILDS_EXPORT}"
echo "MANIFEST:"
sort "${BINHOST}/.manifest"