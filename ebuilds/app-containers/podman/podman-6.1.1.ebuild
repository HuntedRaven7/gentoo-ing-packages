# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/containers/podman"
SRC_URI="https://github.com/containers/podman/archive/refs/tags/v${PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/podman-v${PV}"


src_install() {
	default
}
