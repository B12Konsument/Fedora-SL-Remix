#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib.sh
source "$PROJECT_ROOT/scripts/lib.sh"

assets=$(realpath -- "${1:?release assets directory required}")
layout=$assets/personalization-layout.json
[[ -f $layout ]] || die 'release assets are missing personalization-layout.json'

for kind in windows linux; do
    name=$(jq -er ".${kind}_bundle.name" "$layout")
    size=$(jq -er ".${kind}_bundle.size" "$layout")
    hash=$(jq -er ".${kind}_bundle.sha256" "$layout")
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]+$ && $name != *..* ]] || die "unsafe $kind bundle name"
    [[ -f $assets/$name ]] || die "$kind bundle is missing"
    [[ $(stat -c %s "$assets/$name") == "$size" ]] || die "$kind bundle size mismatch"
    [[ $(sha256sum "$assets/$name" | cut -d' ' -f1) == "$hash" ]] || die "$kind bundle hash mismatch"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/sl7-release-verify.XXXXXX")
cleanup() {
    find "$work" -depth -delete
}
trap cleanup EXIT

unzip -q "$assets/$(jq -r '.windows_bundle.name' "$layout")" -d "$work"
tar -xzf "$assets/$(jq -r '.linux_bundle.name' "$layout")" -C "$work" --no-same-owner --no-same-permissions
[[ -f $work/windows/New-FedoraSl7Iso.ps1 && -f $work/windows/FedoraSl7Remix.psm1 ]] ||
    die 'Windows bundle is missing its expected entrypoint or module'
entrypoint=$(jq -r '.linux_bundle.entrypoint' "$layout")
[[ $entrypoint == linux/new-fedora-sl7-iso.sh && -x $work/$entrypoint && -f $work/linux/lib.sh ]] ||
    die 'Linux bundle is missing its expected executable entrypoint or library'

prohibited=$(find "$work" -type f \( -iname '*.msi' -o -iname '*.mbn' -o -iname '*.elf' -o -iname '*.jsn' -o -name '*.iso' \) -print -quit)
[[ -z $prohibited ]] || die "release bundle contains prohibited private or Microsoft material: $prohibited"
if find "$work" -type f -path '*/fixtures/*' -print -quit | grep -q .; then
    die 'release bundle contains private test fixtures'
fi

bash -n "$work/linux/install.sh" "$work/linux/lib.sh" "$work/linux/new-fedora-sl7-iso.sh"
log 'Verified redistribution-safe Windows and Linux release bundles'
