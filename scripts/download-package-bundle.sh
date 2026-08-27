#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"
source "$PROJECT_ROOT/scripts/github-release-lib.sh"

requested=${1:-latest}
destination="$(realpath -m -- "${2:-.}")"
mkdir -p "$destination"

release="$(release_json "$requested")"
bundle="$(download_asset "$release" 'Fedora-SL7-Remix-packages-.*[.]tar[.]zst$' "$destination")"
checksums="$(download_asset "$release" '^SHA256SUMS$' "$destination")"
expected="$(awk -v name="$(basename "$bundle")" '$2 == name {print $1}' "$checksums")"
[[ -n "$expected" ]] || die "no checksum was published for $(basename "$bundle")"
verify_sha256 "$bundle" "$expected"
printf '%s\n' "$bundle"

