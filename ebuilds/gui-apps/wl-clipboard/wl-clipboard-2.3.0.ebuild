# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Copy and paste utilities for Wayland"
HOMEPAGE="https://github.com/bugaevc/wl-clipboard"
SRC_URI="https://github.com/bugaevc/wl-clipboard/archive/refs/tags/v${PV}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/wl-clipboard-v${PV}"


src_install() {
	default
}
