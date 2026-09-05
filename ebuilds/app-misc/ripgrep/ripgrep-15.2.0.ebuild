# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo

DESCRIPTION="Recursively search directories for a regex pattern"
HOMEPAGE="https://github.com/BurntSushi/ripgrep"
SRC_URI="https://github.com/BurntSushi/ripgrep/archive/refs/tags/${PV}.tar.gz"

LICENSE="Unlicense"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="dev-lang/rust:="


