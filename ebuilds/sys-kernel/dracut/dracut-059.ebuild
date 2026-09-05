# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo

DESCRIPTION=""
HOMEPAGE="https://github.com/dracutdevs/dracut"
SRC_URI="https://github.com/dracutdevs/dracut/archive/refs/tags/${PV}.tar.gz"

LICENSE=""
SLOT="0"
KEYWORDS="~amd64"

DEPEND="dev-lang/rust:="


