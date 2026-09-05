# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Boot and upgrade a Linux system via container images"
HOMEPAGE="https://github.com/containers/bootc"
SRC_URI="https://github.com/bootc-dev/bootc/releases/download/v${PV}/${P}.tar.zstd"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/${P}.tar.zstd"

inherit git-r3

EGIT_REPO_URI="https://github.com/containers/bootc.git"
EGIT_CLONE_TYPE="shallow"
EGIT_BRANCH="main"


    dev-lang/rust-bin
    dev-build/make
    virtual/pkgconfig
"
    >=dev-util/ostree-2024.6
    dev-libs/glib
    sys-libs/libselinux
"
    dev-util/ostree
    app-containers/skopeo
"

src_compile() {
    emake VERSION="${PV}"
}

src_install() {
    emake VERSION="${PV}" DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
}
