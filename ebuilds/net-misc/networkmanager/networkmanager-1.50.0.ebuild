# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Network connection manager and user applications"
HOMEPAGE="https://wiki.gnome.org/Projects/NetworkManager"
SRC_URI="https://download.gnome.org/sources/NetworkManager/1.50/NetworkManager-${PV}.tar.xz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/NetworkManager-${PV}"


src_install() {
	default
}
