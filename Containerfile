# gentoo-ing-packages - curated Gentoo binary package host (binhost) for gentoo-ing.
#
# This image has TWO jobs:
#
# 1. BUILD the gap set (config/gap-build.txt) — packages the official Gentoo
#    binhost does not ship (bootc, kernel, firmware, skopeo, flatpak, iwd, jq,
#    gum, just). They are compiled here, once per published image, and cached
#    as binpkgs so gentoo-ing never compiles anything itself.
# 2. PUBLISH a data-only image containing the finished binhost tree plus the
#    ebuild overlay that gives consumers atom visibility for the packages
#    ::gentoo does not carry at all (bootc, gum, just).
#
#   /var/cache/binhost/gentoo-ing          -> binpkg tree + Packages index
#   /var/cache/binhost/gentoo-ing-ebuilds  -> ebuild overlay (repo_name,
#                                             metadata/layout.conf, ebuilds)
#
# gentoo-ing consumes it with `COPY --from=` pinned by digest, the same way the
# finpilot factory pulls projectbluefin/common and ublue-os/brew.
#
# The official Gentoo binhost still does the heavy lifting: it supplies the
# dependency binaries for the gap builds, and consumers resolve most packages
# from it directly (priority 9999, below this overlay's 10000).

ARG GENTOO_IMAGE="gentoo/stage3:systemd"
FROM ${GENTOO_IMAGE} AS maker

# The scheduled update cycle (publish.yml cron) passes SYNC_PORTAGE=1 to refresh
# the portage tree before the emerge, so -uDN discovers version bumps.
ARG SYNC_PORTAGE="0"
ENV SYNC_PORTAGE=${SYNC_PORTAGE}

# The binhost location. Matches the `location` key that consumers configure in
# /etc/portage/binrepos.conf.
ENV PKGDIR="/var/cache/binhost/gentoo-ing"

# stage3 docker images are stripped: no portage tree ships. Bootstrap a
# snapshot here in its own layer so source changes do not pay the sync cost
# (the weekly cycle forces a fresh one with SYNC_PORTAGE=1).
RUN emerge-webrsync

COPY tools /app/tools
COPY config /app/config
COPY ebuilds /app/ebuilds
COPY packages /app/packages

# Bootstrap portage, build the gap closure as binpkgs, regenerate the index
# (strict: a corrupt tbz2 breaks the image so it never reaches consumers).
RUN chmod +x /app/tools/make-binpkg.sh \
    && /app/tools/make-binpkg.sh \
    && test -f "${PKGDIR}/Packages"

# Publish only the binhost tree + the ebuild overlay.
FROM scratch AS binhost

COPY --from=maker /var/cache/binhost/gentoo-ing /var/cache/binhost/gentoo-ing
COPY --from=maker /var/cache/binhost/gentoo-ing-ebuilds /var/cache/binhost/gentoo-ing-ebuilds