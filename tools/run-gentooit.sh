#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENTOOIT_DIR="${REPO_ROOT}/tools/gentooit"
GENTOOIT_BIN="${GENTOOIT_DIR}/target/release/gentooit"

if [ ! -x "${GENTOOIT_BIN}" ]; then
    echo "gentooit binary not found. Build it first with:" >&2
    echo "  cd ${GENTOOIT_DIR} && cargo build --release" >&2
    exit 1
fi

export GENTOOIT_GITHUB_TOKEN="${GENTOOIT_GITHUB_TOKEN:-${GH_TOKEN:-}}"
exec "${GENTOOIT_BIN}" "$@"
