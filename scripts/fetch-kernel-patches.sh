#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command curl
require_command jq
mkdir -p "$BUILD_ROOT/kernel-patches"

while IFS= read -r patch_json; do
    id="$(jq -r .id <<<"$patch_json")"
    if [[ "$(jq -r 'has("path")' <<<"$patch_json")" == true ]]; then
        path="$PROJECT_ROOT/$(jq -r .path <<<"$patch_json")"
        [[ -f "$path" ]] || die "local kernel patch is missing: $path"
        continue
    fi

    url="$(jq -r .url <<<"$patch_json")"
    expected="$(jq -r .sha256 <<<"$patch_json")"
    destination="$BUILD_ROOT/kernel-patches/$id.patch"
    if [[ ! -f "$destination" ]]; then
        log "Downloading kernel patch $id"
        curl --fail --location --retry 3 --output "$destination.partial" "$url"
        mv "$destination.partial" "$destination"
    fi
    verify_sha256 "$destination" "$expected"
done < <(jq -c '.patches[]' "$PROJECT_ROOT/kernel/series.json")

