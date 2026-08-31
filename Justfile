export IMAGE_NAME := env("IMAGE_NAME", "gentoo-ing-packages")
export REPO_ORG := env("REPO_ORG", "HuntedRaven7")
export IMAGE_FULL := "ghcr.io/" + REPO_ORG + "/" + IMAGE_NAME
export PODMAN := env("PODMAN", "podman")

[private]
default:
    @just --list

# Validate config, ebuild overlay, and binhost tree consistency
[group('Just')]
validate:
    python3 tools/validate.py

# Lint shell tooling and byte-compile python tooling
[group('Just')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if command -v shellcheck >/dev/null 2>&1; then
        find tools -name '*.sh' -type f -exec shellcheck {} +
    fi
    python3 -m py_compile tools/seed-binhost.py tools/validate.py

# Build the binhost image locally (mirrors + compiles the full overlay set).
# ccache primes from .cache/ccache (a prior `just prime-cache`); a cold
# first build starts with an empty cache, just like a first CI run.
[group('Image')]
build $tag="latest":
    mkdir -p .cache/ccache
    {{ PODMAN }} build --pull=newer \
        --build-context ccache-prime=.cache/ccache \
        -t localhost/{{ IMAGE_NAME }}:{{ tag }} .

# Pull the ccache out of a prior local build's maker stage into .cache/ccache
# so the next `just build` reuses it. No-op (exit 0) if no maker image yet.
[group('Image')]
prime-cache:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p .cache/ccache
    cid=$("{{ PODMAN }}" create localhost/{{ IMAGE_NAME }}:maker /bin/sh 2>/dev/null) || exit 0
    "{{ PODMAN }}" cp "${cid}:/var/cache/ccache/." .cache/ccache/ || true
    "{{ PODMAN }}" rm "${cid}" >/dev/null
    du -sh .cache/ccache

# Push the binhost image to GHCR
[group('Image')]
push $tag="latest":
    {{ PODMAN }} push localhost/{{ IMAGE_NAME }}:{{ tag }} {{ IMAGE_FULL }}:{{ tag }}

# Stage official prebuilts into packages/ (only for atoms the official host carries)
[group('Tooling')]
seed binhost_root="" BASE="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64":
    python3 tools/seed-binhost.py {{ if binhost_root == "" { BASE } else { binhost_root } }}

# Show the full overlay set the factory mirrors/builds (gentoo-ing parity)
[group('Tooling')]
show-package-set:
    sed -e '/^#/d' -e '/^[[:space:]]*$/d' config/packages.txt

# Show the never-ship build-time-only toolchains pruned from the cache
[group('Tooling')]
show-prune-list:
    sed -e '/^#/d' -e '/^[[:space:]]*$/d' config/prune.txt