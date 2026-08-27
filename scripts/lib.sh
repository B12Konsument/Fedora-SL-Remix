#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail

if [[ -z ${PROJECT_ROOT:-} ]]; then
    PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
readonly PROJECT_ROOT
readonly BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/.build}"
readonly SOURCE_LOCK="$PROJECT_ROOT/sources.lock.json"

log() {
    printf '[fedora-sl7-remix] %s\n' "$*" >&2
}

warn() {
    printf '[fedora-sl7-remix] warning: %s\n' "$*" >&2
}

die() {
    printf '[fedora-sl7-remix] error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null || die "required command not found: $1"
}

locked_source() {
    local id=$1
    jq -er --arg id "$id" '.sources[] | select(.id == $id)' "$SOURCE_LOCK"
}

verify_sha256() {
    local file=$1 expected=$2
    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    [[ "$actual" == "$expected" ]] || die "SHA-256 mismatch for $file (expected $expected, got $actual)"
}

