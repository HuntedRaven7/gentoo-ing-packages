# Copyright 2026 The gentoo-ing developers
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3

DESCRIPTION="A tool for glamorous shell scripts"
HOMEPAGE="https://github.com/charmbracelet/gum"
EGIT_REPO_URI="https://github.com/charmbracelet/gum.git"
EGIT_CLONE_TYPE="shallow"
EGIT_BRANCH="main"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64"

BDEPEND="dev-lang/go-bin"

src_compile() {
    export CGO_ENABLED=0
    go build -mod=mod -trimpath -ldflags "-s -w" -o gum .
}

src_install() {
    dobin gum
    if [[ -f completions/gum.bash ]]; then
        insinto /usr/share/bash-completion/completions
        doins completions/gum.bash
    fi
    if [[ -f completions/gum.fish ]]; then
        insinto /usr/share/fish/vendor_completions.d
        doins completions/gum.fish
    fi
    if [[ -f completions/gum.zsh ]]; then
        insinto /usr/share/zsh/site-functions
        doins completions/gum.zsh
    fi
    if [[ -f man/gum.1.gz ]]; then
        doman man/gum.1.gz
    fi
}