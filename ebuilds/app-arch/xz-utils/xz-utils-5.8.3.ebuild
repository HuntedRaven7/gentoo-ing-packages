# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="XZ-format compression utilities"
HOMEPAGE="https://tukaani.org/xz/"
SRC_URI="https://github.com/tukaani-project/xz/archive/refs/tags/v${PV}.tar.gz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/xz-v${PV}"


src_install() {
	default
}
