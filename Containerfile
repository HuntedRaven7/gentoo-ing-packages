# gentoo-ing-packages - the full Gentoo binary package host (binhost) for gentoo-ing.
#
# Three stages, three jobs:
#
#   builder  (target)   = the SHARED build environment. Portage tree, profile,
#                         make.conf, vendored ebuild overlay, toolchains
#                         accept_keywords, USE-gap overrides, official binhost
#                         dependency source + signature trust, ccache — baked
#                         once by tools/bootstrap-env.sh. The Build Matrix
#                         workflow builds it through BuildKit with the gha layer
#                         cache, so the very expensive emerge-webrsync +
#                         configuration happens once per repo, then every one
#                         of the ~45 parallel matrix edges reuses the cached
#                         image (works on fork PRs too: no registry write).
#   maker     (target)   = compose + verify. The single-container build of the
#                         FULL set (config/packages.txt), used by the matrix
#                         `publish` job and local `just build`. The matrix
#                         edges' compiled binpkgs arrive via the `packages/`
#                         fast-path staging, so they are INSTALLED as binpkgs
#                         instead of recompiled; everything else is mirrored
#                         from the official host. It re-emits the whole closure,
#                         regenerates the Packages index, prunes stale versions,
#                         and fails closed if the overlay cannot serve the full
#                         declared set.
#   binhost   (default)  = the published data-only image: the binhost tree +
#                         the ebuild overlay bundled at
#                           /var/cache/binhost/gentoo-ing
#                           /var/cache/binhost/gentoo-ing-ebuilds
#
# gentoo-ing consumes it with `COPY --from=` pinned by digest, the same way the
# finpilot factory pulls projectbluefin/common and ublue-os/brew.
#
# ccache (/var/cache/ccache) and distfiles (/var/cache/distfiles) are RUNTIME
# state, never baked: the workflow primes them through the ccache-prime and
# distfiles-prime build contexts and round-trips them through actions/cache,
# which keeps the builder image layers deterministic and cacheable.

ARG GENTOO_IMAGE="gentoo/stage3:systemd"
FROM ${GENTOO_IMAGE} AS builder

# The scheduled update cycle (build-matrix.yml cron) passes SYNC_PORTAGE=1 to
# refresh the portage tree so -uDN discovers version bumps.
ARG SYNC_PORTAGE="0"
ENV SYNC_PORTAGE=${SYNC_PORTAGE}

# The binhost location. Matches the `location` key that consumers configure in
# /etc/portage/binrepos.conf.
ENV PKGDIR="/var/cache/binhost/gentoo-ing"

# stage3 docker images are stripped: no portage tree ships. Bootstrap a
# snapshot here in its own layer so source changes do not pay the sync cost
# (the scheduled update cycle forces a fresh one with SYNC_PORTAGE=1).
RUN emerge-webrsync

COPY tools /app/tools
COPY config /app/config
COPY ebuilds /app/ebuilds
COPY packages /app/packages

# Bake the shared build environment. Deterministic: nothing here depends on the
# cached ccache/distfiles state, so BuildKit layer cache hits across runs.
RUN chmod +x /app/tools/bootstrap-env.sh \
    && /app/tools/bootstrap-env.sh

FROM builder AS maker

# The matrix edges' compiled gap binpkgs, injected through the `binpkg-staging`
# build context (CI: the publish job's collected stage artifacts; local `just
# build`: the repo's own packages/ dir). make-binpkg.sh stages /app/packages
# into PKGDIR first, so these are INSTALLED as binpkgs instead of recompiled.
# The regular context stays small (the artifacts never touch the workspace).
COPY --from=binpkg-staging / /app/packages/

# Prime ccache from the previous run's cache, if any. The publish workflow
# supplies this additional build context (ccache-prime) round-tripped through
# actions/cache; local `just build` does the same from .cache/ccache. An empty
# context primes nothing and simply starts cold.
COPY --from=ccache-prime / /var/cache/ccache/

# Prime distfiles from the previous run's cache, if any. The publish workflow
# supplies this additional build context (distfiles-prime) round-tripped through
# actions/cache; local `just build` does the same from .cache/distfiles. An empty
# context primes nothing and simply starts cold.
COPY --from=distfiles-prime / /var/cache/distfiles/

# Compose and verify the full overlay set (mirrored + compiled gaps) as binpkgs,
# regenerate the index (strict: a corrupt tbz2 breaks the image so it never
# reaches consumers). Fail-closed: a run that cannot serve the full set exits
# non-zero inside make-binpkg.sh.
RUN chmod +x /app/tools/make-binpkg.sh \
    && /app/tools/make-binpkg.sh \
    && test -f "${PKGDIR}/Packages"

# Publish only the binhost tree + the ebuild overlay.
FROM scratch AS binhost

COPY --from=maker /var/cache/binhost/gentoo-ing /var/cache/binhost/gentoo-ing
COPY --from=maker /var/cache/binhost/gentoo-ing-ebuilds /var/cache/binhost/gentoo-ing-ebuilds