# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/ostreedev/ostree"
SRC_URI="https://github.com/ostreedev/ostree/releases/download/v${PV}/lib${P}.tar.xz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/lib${P}"


src_install() {
	default
}
