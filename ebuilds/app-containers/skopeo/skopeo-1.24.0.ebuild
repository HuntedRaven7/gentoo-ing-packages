# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Work with container images and registries"
HOMEPAGE="https://github.com/containers/skopeo"
SRC_URI="https://github.com/containers/skopeo/archive/refs/tags/v${PV}.tar.gz -> skopeo-${PV}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/skopeo-${PV}"


src_install() {
	default
}
