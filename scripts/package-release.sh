#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

iso=${1:?ISO path required}
output=${2:-/output}
version=${BUILD_VERSION:-$(<"$PROJECT_ROOT/VERSION")}
mkdir -p "$output"

bundle="$output/Fedora-SL7-Remix-packages-$version.aarch64.tar.zst"
tar --sort=name --mtime='UTC 2026-08-26' --owner=0 --group=0 --numeric-owner \
    -C "$BUILD_ROOT/repo" --zstd -cf "$bundle" .

cp "$iso" "$output/"

(
    cd "$output"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs -r sha256sum
) > "$output/SHA256SUMS"
