#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /tmp/sl7-release-test.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT

printf 'test ISO payload\n' > "$fixture/test.iso"
sha256="$(sha256sum "$fixture/test.iso" | cut -d' ' -f1)"
jq -n --arg sha256 "$sha256" --argjson size "$(stat -c %s "$fixture/test.iso")" '{
  schema:1,
  base_iso:{name:"test.iso",size:$size,sha256:$sha256,parts:[]},
  windows_bundle:null,
  linux_bundle:null
}' > "$fixture/layout.json"
"$root/scripts/split-release.sh" "$fixture/test.iso" "$fixture/assets" "$fixture/layout.json"
cmp "$fixture/test.iso" "$fixture/assets/test.iso"
jq -e '.base_iso.parts | length == 1' "$fixture/assets/personalization-layout.json" >/dev/null
jq -e '.windows_bundle.name == "windows-customizer.zip"' "$fixture/assets/personalization-layout.json" >/dev/null
jq -e '.linux_bundle.name == "linux-customizer.tar.gz" and
    .linux_bundle.entrypoint == "linux/new-fedora-sl7-iso.sh" and
    .linux_bundle.customizer_version == "0.2.5"' "$fixture/assets/personalization-layout.json" >/dev/null
tar -tzf "$fixture/assets/linux-customizer.tar.gz" | grep -Fxq 'linux/new-fedora-sl7-iso.sh'
(cd "$fixture/assets" && sha256sum -c SHA256SUMS --ignore-missing >/dev/null)
printf 'release split test passed\n'
