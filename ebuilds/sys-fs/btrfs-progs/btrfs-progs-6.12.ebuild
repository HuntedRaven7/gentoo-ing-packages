# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Checks and defragmentation tool for Btrfs filesystem"
HOMEPAGE="https://btrfs.readthedocs.io/"
SRC_URI="https://www.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/btrfs-progs-v${PV}.tar.xz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"
S="${WORKDIR}/btrfs-progs-v${PV}"


src_install() {
	default
}
