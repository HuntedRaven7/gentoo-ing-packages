# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="ext2/3/4 filesystem utilities"
HOMEPAGE="https://e2fsprogs.sourceforge.net/"
SRC_URI="https://github.com/tytso/e2fsprogs/archive/refs/tags/v${PV}.tar.gz -> e2fsprogs-${PV}.tar.gz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/e2fsprogs-${PV}"


src_install() {
	default
}
