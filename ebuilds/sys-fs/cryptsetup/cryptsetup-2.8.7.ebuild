# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Disk encryption"
HOMEPAGE="https://gitlab.com/cryptsetup/cryptsetup"
SRC_URI="https://github.com/mbroz/cryptsetup/archive/refs/tags/v${PV}.tar.gz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/cryptsetup-v${PV}"


src_install() {
	default
}
