# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION=""
HOMEPAGE="https://github.com/curl/curl"
SRC_URI="https://github.com/curl/curl/releases/download/${PV}/curl-8.22.0.zip"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/curl-8.22.0"


src_install() {
	default
}
