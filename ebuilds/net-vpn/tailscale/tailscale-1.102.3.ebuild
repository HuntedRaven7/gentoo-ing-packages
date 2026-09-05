# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo

DESCRIPTION=""
HOMEPAGE="https://github.com/tailscale/tailscale"
SRC_URI="https://github.com/tailscale/tailscale/archive/refs/tags/v${PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/tailscale-v${PV}"

DEPEND="dev-lang/rust:="


