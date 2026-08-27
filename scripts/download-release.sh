#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"
source "$PROJECT_ROOT/scripts/github-release-lib.sh"

requested=${1:-latest}
destination="$(realpath -m -- "${2:-$PROJECT_ROOT/out}")"
mkdir -p "$destination"
release="$(release_json "$requested")"
checksums="$(download_asset "$release" '^SHA256SUMS$' "$destination")"

mapfile -t urls < <(jq -r '.assets[] | select(.name | test("[.]iso([.]part-[0-9]+)?$")) | .browser_download_url' <<<"$release" | sort)
((${#urls[@]})) || die 'this release contains no ISO assets'

parts=()
for url in "${urls[@]}"; do
    name="$(basename "$url")"
    file="$destination/$name"
    curl --fail --location --retry 3 --output "$file.partial" "$url"
    mv "$file.partial" "$file"
    expected="$(awk -v n="$name" '$2 == n {print $1}' "$checksums")"
    [[ -n "$expected" ]] || die "no checksum was published for $name"
    verify_sha256 "$file" "$expected"
    parts+=("$file")
done

if [[ ${parts[0]} == *.part-* ]]; then
    iso_name="$(basename "${parts[0]}" | sed 's/[.]part-[0-9][0-9]*$//')"
    partial="$destination/$iso_name.partial"
    cat "${parts[@]}" > "$partial"
    expected="$(awk -v n="$iso_name" '$2 == n {print $1}' "$checksums")"
    [[ -n "$expected" ]] || die "no final ISO checksum was published for $iso_name"
    verify_sha256 "$partial" "$expected"
    mv "$partial" "$destination/$iso_name"
    printf '%s\n' "$destination/$iso_name"
else
    printf '%s\n' "${parts[0]}"
fi

