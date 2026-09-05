# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/jqlang/jq"
SRC_URI="https://github.com/jqlang/jq/archive/refs/tags/${P}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/jq-${P}"


src_install() {
	default
}
