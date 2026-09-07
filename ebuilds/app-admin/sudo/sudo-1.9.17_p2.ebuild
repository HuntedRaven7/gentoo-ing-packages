# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/sudo-project/sudo"
MY_PV="1.9.17p2"
SRC_URI="https://github.com/sudo-project/sudo/releases/download/v${MY_PV}/${PN}-${MY_PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/${PN}-${MY_PV}"


src_install() {
	default
}
