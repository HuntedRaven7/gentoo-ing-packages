# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="OpenSSH is a FREE version of the SSH connectivity tools"
HOMEPAGE="https://www.openssh.com/"
SRC_URI="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${P}.tar.gz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"


src_install() {
	default
}
