#!/usr/bin/env bash
set -euo pipefail

# One matrix edge: compile a single atom inside the shared `builder` image.
#
# Every edge installs the SAME environment (bootstrap-env.sh baked into the
# image: tree, profile, make.conf, official binhost as dependency source,
# signature trust, ccache) and then:
#
#   - registers the previous stages' artifacts (a PKGDIR-shaped binrepo) ABOVE
#     the official host, so an intra-set dependency this factory must compile
#     resolves from /prior instead of being compiled again on every edge;
#   - points PKGDIR at RESULT_DIR, so this edge's output is collected and
#     uploaded as the binpkg-s<N>-<package> artifact;
#   - stages any plopped-in .tbz2 from packages/ first (prebuilt wins);
#   - emerges the atom with the strict consumer --binpkg-respect-use=y;
#   - fails closed if no binpkg was produced for the atom.
#
# Env: PACKAGE (cat/pkg), RESULT_DIR (PKGDIR), PRIOR_DIR (optional earlier-stage
# binrepo). ccache + distfiles are runtime mounts at the default locations the
# baked make.conf already points at.

: "${PACKAGE:?PACKAGE is required}"
: "${RESULT_DIR:?RESULT_DIR is required}"
PRIOR_DIR="${PRIOR_DIR:-}"

# 1. Earlier-stage artifacts as a binrepo, preferred above the official host
#    (binrepo priority: higher wins; official is 9999, consumer is 10000).
if [ -n "${PRIOR_DIR}" ] && [ -d "${PRIOR_DIR}" ] \
    && find "${PRIOR_DIR}" \( -name '*.tbz2' -o -name '*.gpkg.tar' \) -print -quit | grep -q .; then
    mkdir -p /etc/portage/binrepos.conf
    cat > /etc/portage/binrepos.conf/prior.conf <<EOF
[prior]
priority = 10000
sync-uri = file://${PRIOR_DIR}
verify-signature = false
location = /var/cache/binhost/prior
EOF
    echo "PRIOR: registered ${PRIOR_DIR} as binrepo (priority 10000)"
fi

# 2. Result PKGDIR. Override the baked default so only THIS edge's output is
#    collected and uploaded.
mkdir -p "${RESULT_DIR}"
if grep -q '^PKGDIR=' /etc/portage/make.conf; then
    sed -i "s|^PKGDIR=.*|PKGDIR=${RESULT_DIR}|" /etc/portage/make.conf
else
    echo "PKGDIR=${RESULT_DIR}" >> /etc/portage/make.conf
fi

# 3. Stage any plopped-in .tbz2 from packages/ (make-binpkg.sh parity:
#    prebuilt starting points win over compiling this atom).
if [ -d /app/packages ] && find /app/packages \( -name '*.tbz2' -o -name '*.gpkg.tar' \) -print -quit | grep -q .; then
    cp -avf /app/packages/. "${RESULT_DIR}/"
fi
# Index the (possibly staged) result so the uploaded artifact carries a valid
# Packages index for downstream stages to consume as their /prior binrepo.
# (emaint indexes the PKGDIR set in make.conf; --dir is not an emaint option.)
emaint binhost --fix || true

# 4. Build the atom. Deps resolve from /prior (this factory) > official binhost
#    > source, all behind the strict --binpkg-respect-use=y the consumer uses.
#    Deliberately NO --deep: this is a per-atom edge, not a world refresh.
#    --deep would re-scan the ENTIRE installed world in every one of the ten
#    parallel edges, pull each whole closure into each transaction, and (with
#    the 2026 tree's hard glib/docutils/pillow/harfbuzz cycle) force a fresh
#    glib to be merged alongside its build-time deps in a single transaction
#    portage cannot order. --update scoped to the atom builds exactly this
#    package plus whatever the strict resolution is missing; the compose
#    (make-binpkg.sh -uDN over the full set) is the single whole-world refresh.
emerge --update --newuse "${PACKAGE}"

atom=$(basename "${PACKAGE}")

# 5. Fail-closed: the atom must actually have a binpkg in the result.
if ! find "${RESULT_DIR}" -type f \( -name "${atom}-*.tbz2" -o -name "${atom}-*.gpkg.tar" \) | grep -q .; then
    echo "FATAL: no binpkg produced for ${PACKAGE}" >&2
    exit 1
fi

# 6. Slim the result to THIS atom's own binpkg(s). --buildpkg also re-emits the
#    whole merged dependency closure (mostly official-mirror bins) into
#    RESULT_DIR; uploading that on every parallel edge would mean tens of GB of
#    duplicated artifacts. The compose (make-binpkg.sh) re-mirrors dependencies
#    itself — the edges' only contribution is the compiled gap.
find "${RESULT_DIR}" -type f \( -name '*.tbz2' -o -name '*.gpkg.tar' \) ! -name "${atom}-*" -delete
find "${RESULT_DIR}" -type d -empty -delete

# 7. Report
count=$(find "${RESULT_DIR}" \( -name '*.tbz2' -o -name '*.gpkg.tar' \) | wc -l)
echo "MATRIX: ${PACKAGE} produced ${count} binpkg(s) in ${RESULT_DIR}"
find "${RESULT_DIR}" \( -name '*.tbz2' -o -name '*.gpkg.tar' \) | sort