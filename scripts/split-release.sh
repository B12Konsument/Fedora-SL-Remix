#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
iso=${1:?ISO path required}
destination="$(realpath -m -- "${2:?destination required}")"
layout="$(realpath -- "${3:?personalization layout required}")"
mkdir -p "$destination"
base="$(basename "$iso")"

if (( $(stat -c %s "$iso") > 1900 * 1024 * 1024 )); then
    split -b 1900M -d -a 3 "$iso" "$destination/$base.part-"
else
    cp "$iso" "$destination/$base"
fi

bundle="$destination/windows-customizer.zip"
(
    cd "$PROJECT_ROOT"
    zip -q -X -r "$bundle" windows
)

parts_json="$destination/parts.json"
find "$destination" -maxdepth 1 -type f \
    \( -name "$base" -o -name "$base.part-*" \) -printf '%f\n' | sort | while IFS= read -r part; do
    jq -n \
        --arg name "$part" \
        --arg sha256 "$(sha256sum "$destination/$part" | cut -d' ' -f1)" \
        --argjson size "$(stat -c %s "$destination/$part")" \
        '{name:$name,size:$size,sha256:$sha256}'
done | jq -s . > "$parts_json"

jq \
    --slurpfile parts "$parts_json" \
    --arg bundle_name "$(basename "$bundle")" \
    --arg bundle_sha256 "$(sha256sum "$bundle" | cut -d' ' -f1)" \
    --argjson bundle_size "$(stat -c %s "$bundle")" \
    '.base_iso.parts=$parts[0] | .windows_bundle={name:$bundle_name,size:$bundle_size,sha256:$bundle_sha256}' \
    "$layout" > "$destination/personalization-layout.json"
find "$parts_json" -delete

(
    cd "$destination"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs -r sha256sum
) > "$destination/SHA256SUMS"
