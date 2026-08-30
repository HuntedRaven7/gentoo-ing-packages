#!/usr/bin/env bash
set -euo pipefail

# Build the gentoo-ing binhost overlay: compile the gap set (config/gap-build.txt)
# that the official Gentoo binhost does not ship, publish them as a self-contained
# binpkg tree, and export the vendored ebuild overlay for consumer atom visibility.
#
# Designed to run on every publish AND on the weekly update cycle (SYNC_PORTAGE=1):
#   - a fresh tree sync makes -uDN discover version bumps
#   - --buildpkg only emits a binpkg for what actually merged (unchanged packages
#     are not re-packaged, so unchanged runs are cheap + cached)
#   - prune-binhost.py keeps only the newest version per package, so the published
#     image stays bounded (no stacked superseded tbz2s)
#   - .manifest is the byte-stable summary the workflow diffs to skip no-op pushes

BINHOST="/var/cache/binhost/gentoo-ing"
EBUILDS="/app/ebuilds"
EBUILDS_EXPORT="/var/cache/binhost/gentoo-ing-ebuilds"
OFFICIAL_BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/"
BRANCH_PROFILE="default/linux/amd64/23.0/systemd"

# 1. Portage tree. stage3 images ship a snapshot; SYNC_PORTAGE fetches a fresh
#    one for the weekly update cycle.
if [ ! -d /var/db/repos/gentoo/profiles ]; then
    emerge-webrsync || emerge --sync
elif [ "${SYNC_PORTAGE:-0}" = "1" ]; then
    emerge-webrsync || emerge --sync
fi

# 2. Profile
rm -f /etc/portage/make.profile
ln -s "/var/db/repos/gentoo/profiles/${BRANCH_PROFILE}" /etc/portage/make.profile

# 3. make.conf. Binpkg-respect-use=n: the official deps are accepted as-is so
# only the gap atoms compile. --buildpkg emits every merged package into
# PKGDIR (the overlay is then self-contained for its guaranteed set).
touch /etc/portage/make.conf
grep -q '^ACCEPT_LICENSE=' /etc/portage/make.conf \
    || echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
grep -q '^PKGDIR=' /etc/portage/make.conf \
    || echo "PKGDIR=${BINHOST}" >> /etc/portage/make.conf
grep -q '^FEATURES=.*getbinpkg' /etc/portage/make.conf \
    || echo 'FEATURES="-manifest getbinpkg binpkg-multi-instance parallel-fetch parallel-install"' >> /etc/portage/make.conf
# shellcheck disable=SC2016 # $(nproc) must reach make.conf unevaluated
grep -q '^MAKEOPTS=' /etc/portage/make.conf \
    || echo 'MAKEOPTS="-j$(nproc)"' >> /etc/portage/make.conf
grep -q '^EMERGE_DEFAULT_OPTS=' /etc/portage/make.conf \
    || echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --buildpkg --binpkg-respect-use=n --binpkg-native-symlinks"' >> /etc/portage/make.conf

# 4. Vendored ebuild overlay (bootc, gum, just) so the gap atoms resolve.
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo-ing-ebuilds.conf <<EOF
[gentoo-ing-ebuilds]
location = ${EBUILDS}
sync-type = none
priority = 80
EOF

# Toolchain atoms used to compile the gaps may trail the stable branch on
# amd64. Accept ~amd64 for THOSE ONLY, so the gap binaries themselves stay
# stable-visible to consumers (they only ever consume the finished binpkg).
mkdir -p /etc/portage/package.accept_keywords
echo '=dev-lang/rust-bin-* ~amd64' > /etc/portage/package.accept_keywords/toolchains
echo '=dev-lang/go-bin-* ~amd64' >> /etc/portage/package.accept_keywords/toolchains
echo '=dev-lang/go-* ~amd64' >> /etc/portage/package.accept_keywords/toolchains

# 5. Official binhost supplies dependency binaries for the gap builds.
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoo.conf <<EOF
[gentoo]
priority = 9999
sync-uri = ${OFFICIAL_BINHOST}
verify-signature = false
location = /var/cache/binhost/gentoo
EOF

# 6. Stage any plopped-in .tbz2 first (faster prebuilt starting points).
mkdir -p "${BINHOST}"
if find /app/packages -name '*.tbz2' -o -name '*.gpkg.tar' | grep -q .; then
    cp -avf /app/packages/. "${BINHOST}/"
fi

# 7. Update (no-op when nothing is stale) and emit binpkgs for what merged.
#    Deps come from the official binhost as binaries; only atoms the official
#    host lacks actually compile here.
mapfile -t GAPS < <(sed -e '/^#/d' -e '/^[[:space:]]*$/d' /app/config/gap-build.txt)
if [ "${#GAPS[@]}" -gt 0 ]; then
    emerge --update --deep --newuse "${GAPS[@]}"
fi

# 8. Regenerate the Packages index. Strict: a corrupt tbz2 fails the image.
emaint binhost --fix

# 9. Prune superseded versions (bounds the image) and re-index.
python3 /app/tools/prune-binhost.py --binhost "${BINHOST}"
emaint binhost --fix

# 10. Export the ebuild overlay for consumers (atom visibility for bootc/gum/just).
mkdir -p "${EBUILDS_EXPORT}"
cp -avf "${EBUILDS}/." "${EBUILDS_EXPORT}/"

# 11. Report
count=$(find "${BINHOST}" -name '*.tbz2' -o -name '*.gpkg.tar' | wc -l)
echo "OVERLAY: ${count} binpkg(s) in ${BINHOST}"
echo "EBUILDS: exported to ${EBUILDS_EXPORT}"
echo "MANIFEST:"
sort "${BINHOST}/.manifest"