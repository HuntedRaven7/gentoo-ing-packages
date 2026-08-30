# Copyright 2026 The gentoo-ing developers
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3

DESCRIPTION="Handy way to save and run project-specific commands"
HOMEPAGE="https://github.com/casey/just"
EGIT_REPO_URI="https://github.com/casey/just.git"
EGIT_CLONE_TYPE="shallow"
EGIT_BRANCH="main"

LICENSE="CC0-1.0"
SLOT="0"
KEYWORDS="amd64"

BDEPEND="dev-lang/rust-bin"

src_compile() {
    cargo build --release --locked --bin just
    ./target/release/just --completions bash > "${T}/just.bash"
    ./target/release/just --completions fish > "${T}/just.fish"
    ./target/release/just --completions zsh > "${T}/just.zsh"
    ./target/release/just --man > "${T}/just.1"
}

src_install() {
    dobin target/release/just
    insinto /usr/share/bash-completion/completions
    doins "${T}/just.bash"
    insinto /usr/share/fish/vendor_completions.d
    doins "${T}/just.fish"
    insinto /usr/share/zsh/site-functions
    doins "${T}/just.zsh"
    doman "${T}/just.1"
}