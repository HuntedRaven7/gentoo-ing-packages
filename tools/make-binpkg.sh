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
#     carries with matching USE (no wasteful recompiles); atoms whose USE diverge
#     or that it lacks (the desktop/GNOME closure) are compiled here
#   - --buildpkg emits a binpkg for every merged package (atoms AND dependency
#     closure), so the overlay is the consumer's only source
#   - unchanged packages are not re-packaged, so unchanged runs are cheap + cached
#   - prune-binhost.py keeps only the newest version per package AND drops the
#     build-time-only toolchains in config/prune.txt (rust/go, never needed by a
#     --usepkgonly consumer), so the published image stays small
#   - .manifest is the byte-stable summary the workflow diffs to skip no-op pushes
#   - ccache (portage's FEATURES=ccache, /usr/lib/ccache/bin) caches compiles
#     under /var/cache/ccache; the workflow round-trips that dir through its
#     cache so unchanged compiles are not re-done every run
#   - fail-closed: a run whose overlay cannot serve the FULL declared set (empty
#     manifest or any config/packages.txt atom absent) exits non-zero, so a
#     partial overlay never gets published to the sealed consumer

BINHOST="/var/cache/binhost/gentoo-ing"
EBUILDS="/app/ebuilds"
EBUILDS_EXPORT="/var/cache/binhost/gentoo-ing-ebuilds"

# 1-7. Shared build environment (tree, profile, make.conf, repos.conf, keywords,
#      USE overrides, official binhost as dependency source, signature trust,
#      ccache). Same script the Containerfile `builder` stage and every matrix
#      job use, so the single-container maker and the matrix are identical.
bash /app/tools/bootstrap-env.sh

# 7b. Distfiles cache: if a prior run cached distfiles, symlink them into
#     PORTAGE_DISTCACHE so unchanged source tarballs don't re-download.
if [ -d /var/cache/distfiles ]; then
    mkdir -p /var/cache/distfiles
    ln -sf /var/cache/distfiles /var/cache/ccache/distfiles 2>/dev/null || true
fi

# 8. Stage any plopped-in .tbz2 first (faster prebuilt starting points).
mkdir -p "${BINHOST}"
if find /app/packages -name '*.tbz2' -o -name '*.gpkg.tar' | grep -q .; then
    cp -avf /app/packages/. "${BINHOST}/"
fi

# 9. Build the full overlay set. --getbinpkg mirrors official binaries only
#    where their USE match this profile (--binpkg-respect-use=y); atoms whose
#    USE diverge or that the official host lacks compile (the desktop/GNOME
#    closure). --buildpkg re-emits every merged package (closure included),
#    making the overlay the consumer's sole binrepo.
mapfile -t BUILD_SET < <(sed -e '/^#/d' -e '/^[[:space:]]*$/d' /app/config/packages.txt)
if [ "${#BUILD_SET[@]}" -gt 0 ]; then
    emerge --update --deep --newuse "${BUILD_SET[@]}"
fi

# 10. Ensure EVERY installed package has a binpkg in the overlay -- not just the
#     declared atoms (config/packages.txt) but the full dependency closure.
#     --buildpkg only emits for source builds; packages installed as binaries
#     from the official host (mirrors) never produce a binpkg in PKGDIR. quickpkg
#     repacks every installed CPV still missing from the overlay from the VDB, so
#     the sealed consumer's --usepkgonly can satisfy the ENTIRE closure locally
#     (iptables/nftables/ngtcp2/containers-common included) and the overlay stays
#     genuinely self-contained.
has_binpkg() {
    find "${BINHOST}" -type f \
        \( -name "${1}-*.gpkg.tar" -o -name "${1}-*.tbz2" \) | grep -q .
}
MISSING=()
for cpv in /var/db/pkg/*/*/; do
    cpv=${cpv%/}
    p=${cpv##*/}
    if ! has_binpkg "${p}"; then
        PKGDIR="${BINHOST}" quickpkg --include-config=y "=${cpv#/var/db/pkg/}" 2>/dev/null || true
        if ! has_binpkg "${p}"; then
            MISSING+=("${cpv}")
        fi
    fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    printf 'FATAL: no binpkg for installed package: %s\n' "${MISSING[@]}" >&2
    exit 1
fi

# 11. Regenerate the Packages index. Strict: a corrupt tbz2 fails the image.
emaint binhost --fix

# 12. Prune the cache: drop superseded versions AND build-time-only toolchains
#     (config/prune.txt never-ship list — rust/go/ccache chain), then re-index.
python3 /app/tools/prune-binhost.py --binhost "${BINHOST}" --prune-list /app/config/prune.txt
emaint binhost --fix

# 13. Export the ebuild overlay for consumers (atom visibility for bootc/gum/just).
mkdir -p "${EBUILDS_EXPORT}"
cp -avf "${EBUILDS}/." "${EBUILDS_EXPORT}/"

# 14. Fail-closed: the overlay must actually serve the FULL declared set. A
#     mirror miss or a silent compile failure would leave an atom out; handing
#     a partial overlay to a sealed --usepkgonly consumer bricks its build, so
#     exit non-zero (nothing gets published) instead.
if [ ! -s "${BINHOST}/.manifest" ]; then
    echo "FATAL: no binpkg(s) in overlay; nothing to publish" >&2
    exit 1
fi
for atom in "${BUILD_SET[@]}"; do
    if ! grep -q "^${atom}-" "${BINHOST}/.manifest"; then
        echo "FATAL: ${atom} missing from overlay; not publishing a partial cache" >&2
        exit 1
    fi
done

# 15. Report
count=$(find "${BINHOST}" -name '*.tbz2' -o -name '*.gpkg.tar' | wc -l)
echo "OVERLAY: ${count} binpkg(s) in ${BINHOST}"
echo "EBUILDS: exported to ${EBUILDS_EXPORT}"
echo "MANIFEST:"
sort "${BINHOST}/.manifest"