#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
checker="$root/scripts/check-prohibited-content.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

scan="$work/scan"
mkdir -p "$scan/usr/lib/firmware/qcom/apq8096"
printf '%s' 'freely redistributable fixture' > "$scan/usr/lib/firmware/qcom/apq8096/adspr.jsn"

prohibited_payload='synthetic prohibited content'
payload_size=${#prohibited_payload}
payload_hash="$(printf '%s' "$prohibited_payload" | sha256sum | cut -d' ' -f1)"
denylist="$work/denylist.json"
jq -n --arg hash "$payload_hash" --argjson size "$payload_size" \
    '{schema:1, files:[{name:"adspr.jsn", size:$size, sha256:$hash}]}' > "$denylist"

"$checker" "$denylist" "$scan"

expect_failure() {
    local expected=$1
    shift
    local report="$work/failure.txt"
    if "$@" >"$report" 2>&1; then
        printf 'Expected command to fail: %s\n' "$*" >&2
        exit 1
    fi
    grep -Fq "$expected" "$report" || {
        cat "$report" >&2
        printf 'Expected failure text was not found: %s\n' "$expected" >&2
        exit 1
    }
}

mkdir -p "$scan/usr/lib/firmware/qcom/x1e80100/microsoft/Romulus"
printf '%s' 'different content' > "$scan/usr/lib/firmware/qcom/x1e80100/microsoft/Romulus/other.bin"
expect_failure 'device-specific Microsoft firmware path' "$checker" "$denylist" "$scan"
rm -rf -- "$scan/usr/lib/firmware/qcom/x1e80100"

printf '%s' "$prohibited_payload" > "$scan/renamed.bin"
expect_failure 'known Microsoft firmware content' "$checker" "$denylist" "$scan"
rm -f -- "$scan/renamed.bin"

printf '%s' 'synthetic installer' > "$scan/firmware.msi"
expect_failure 'contains a Microsoft MSI' "$checker" "$denylist" "$scan"

printf 'Prohibited-content tests passed\n'
