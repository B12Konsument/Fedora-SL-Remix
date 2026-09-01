#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

iso=${1:?ISO path required}
layout=${2:?personalization layout required}
output=${3:-/output}
mkdir -p "$output"

cp "$iso" "$output/"
cp "$layout" "$output/personalization-layout.json"

(
    cd "$output"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs -r sha256sum
) > "$output/SHA256SUMS"
