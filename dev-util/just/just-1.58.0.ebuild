# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo

DESCRIPTION="Handy way to save and run project-specific commands"
HOMEPAGE="https://github.com/casey/just"
SRC_URI="https://github.com/casey/just/archive/refs/tags/${PV}.tar.gz"

LICENSE="CC0-1.0"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="dev-lang/rust:="


