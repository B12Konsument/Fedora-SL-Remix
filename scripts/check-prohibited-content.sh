#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command jq
require_command sha256sum

denylist=${1:?Denylist path required}
shift
(($# > 0)) || die 'at least one scan root is required'
[[ -r $denylist ]] || die "proprietary-firmware denylist is missing: $denylist"
scan_roots=("$@")

microsoft_msi="$(find "${scan_roots[@]}" -xdev -type f -iname '*.msi' -print -quit)"
[[ -z $microsoft_msi ]] || die "base ISO contains a Microsoft MSI: $microsoft_msi"

# The generic Qualcomm linux-firmware package may contain filenames that also
# occur in Microsoft's device package. Only the device-specific destination
# path is inherently prohibited; content elsewhere is checked by exact hash.
microsoft_firmware="$(find "${scan_roots[@]}" -xdev -type f \
    -ipath '*/qcom/x1e80100/microsoft/*' -print -quit)"
[[ -z $microsoft_firmware ]] || \
    die "base ISO contains a device-specific Microsoft firmware path: $microsoft_firmware"

mapfile -t prohibited_sizes < <(jq -r '[.files[].size] | unique[]' "$denylist")
size_expression=()
for size in "${prohibited_sizes[@]}"; do
    ((${#size_expression[@]} == 0)) || size_expression+=(-o)
    size_expression+=(-size "${size}c")
done

((${#size_expression[@]} > 0)) || die 'proprietary-firmware denylist has no file sizes'
while IFS= read -r -d '' candidate; do
    candidate_hash="$(sha256sum "$candidate" | cut -d' ' -f1)"
    if jq -e --arg hash "$candidate_hash" '.files[] | select(.sha256 == $hash)' "$denylist" >/dev/null; then
        die "base ISO contains known Microsoft firmware content: $candidate"
    fi
done < <(find "${scan_roots[@]}" -xdev -type f \( "${size_expression[@]}" \) -print0)
