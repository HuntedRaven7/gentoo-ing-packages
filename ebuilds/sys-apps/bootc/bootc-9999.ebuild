# Copyright 2026 The gentoo-ing developers
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3

DESCRIPTION="Boot and upgrade a Linux system via container images"
HOMEPAGE="https://github.com/containers/bootc"
EGIT_REPO_URI="https://github.com/containers/bootc.git"
EGIT_CLONE_TYPE="shallow"
EGIT_BRANCH="main"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="amd64"

BDEPEND="
    dev-lang/rust-bin
    sys-devel/make
    virtual/pkgconfig
"
DEPEND="
    >=dev-util/ostree-2024.6
    dev-libs/glib
"
RDEPEND="
    dev-util/ostree
    app-containers/skopeo
"

src_compile() {
    emake VERSION="${PV}"
}

src_install() {
    emake VERSION="${PV}" DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
}