# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/systemd/systemd"
MY_PV="262-rc1"
SRC_URI="https://github.com/systemd/systemd/archive/refs/tags/v${MY_PV}.tar.gz -> systemd-${MY_PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/systemd-${MY_PV}"


src_install() {
	default
}
