# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/systemd/systemd"
SRC_URI="https://github.com/systemd/systemd/archive/refs/tags/v${PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/systemd-v${PV}"


src_install() {
	default
}
