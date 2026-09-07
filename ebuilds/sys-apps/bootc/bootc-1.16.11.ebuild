# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo

DESCRIPTION="Boot and upgrade a Linux system via container images"
HOMEPAGE="https://github.com/containers/bootc"
SRC_URI="
	https://github.com/bootc-dev/bootc/releases/download/v${PV}/${P}.tar.zstd
	https://github.com/bootc-dev/bootc/releases/download/v${PV}/${P}-vendor.tar.zstd
"

LICENSE="Apache-2.0 OR MIT"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="
	app-arch/zstd:=
	dev-libs/glib:=
	dev-libs/openssl:=
	>=dev-util/ostree-2024.6
	sys-libs/libselinux:=
"
RDEPEND="
	${DEPEND}
	app-containers/podman
	app-containers/skopeo
	sys-apps/coreutils
	sys-apps/systemd
	sys-apps/util-linux
"
BDEPEND="
	dev-build/make
	dev-go/go-md2man
	llvm-core/clang
	virtual/pkgconfig
	>=dev-lang/rust-bin-1.82
"

src_unpack() {
	cargo_src_unpack
	# The release bundle ships a cargo vendor tree (including the two git
	# dependencies); move it next to the source like upstream's
	# .cargo/vendor-config.toml expects and enable that config.
	mv "${WORKDIR}/vendor" "${S}/vendor" || die
	cat "${S}/.cargo/vendor-config.toml" >> "${S}/.cargo/config.toml" || die
}

src_compile() {
	emake VERSION="${PV}"
}

src_install() {
	emake VERSION="${PV}" DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
}