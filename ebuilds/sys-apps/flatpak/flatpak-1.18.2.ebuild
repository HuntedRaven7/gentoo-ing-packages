# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Framework for desktop applications on Linux"
HOMEPAGE="https://github.com/flatpak/flatpak"
SRC_URI="https://github.com/flatpak/flatpak/releases/download/${PV}/${P}.tar.xz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"


src_install() {
	default
}
