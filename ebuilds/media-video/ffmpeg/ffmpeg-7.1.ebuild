# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Tools for transcoding, streaming, and playing multimedia content"
HOMEPAGE="https://ffmpeg.org/"
SRC_URI="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${PV}.tar.gz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/FFmpeg-n${PV}"


src_install() {
	default
}
