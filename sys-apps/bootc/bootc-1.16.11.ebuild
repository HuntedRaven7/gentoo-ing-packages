# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Boot and upgrade a Linux system via container images"
HOMEPAGE="https://github.com/containers/bootc"
SRC_URI="https://github.com/bootc-dev/bootc/releases/download/v${PV}/${P}.tar.zstd"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/${P}.tar.zstd"


src_install() {
	default
}
