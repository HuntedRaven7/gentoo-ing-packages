# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="OpenSSH is a FREE version of the SSH connectivity tools"
HOMEPAGE="https://www.openssh.com/"
MY_PV="9.9p2"
SRC_URI="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${PN}-${MY_PV}.tar.gz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/${PN}-${MY_PV}"


src_install() {
	default
}
