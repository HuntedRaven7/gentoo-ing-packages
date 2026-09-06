# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson

DESCRIPTION="Wayland clipboard utilities"
HOMEPAGE="https://github.com/bugaevc/wl-clipboard"
SRC_URI="https://github.com/bugaevc/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="dev-libs/wayland"
RDEPEND="${DEPEND}"
BDEPEND="
	>=dev-libs/wayland-protocols-1.39
	dev-util/wayland-scanner
"

src_configure() {
	local emesonargs=(
		-Dfishcompletiondir="${EPREFIX}/usr/share/fish/vendor_completions.d"
	)
	meson_src_configure
}