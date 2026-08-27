#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
repo=${1:?repository directory required}
output=${2:?output path required}
version=${BUILD_VERSION:-0.0.0}

packages='[]'
while IFS= read -r rpm_file; do
    name="$(rpm -qp --qf '%{NAME}' "$rpm_file")"
    evr="$(rpm -qp --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$rpm_file")"
    checksum="$(sha256sum "$rpm_file" | cut -d' ' -f1)"
    packages="$(jq --arg name "$name" --arg evr "$evr" --arg checksum "$checksum" \
        '. + [{SPDXID:("SPDXRef-Package-" + ($name|gsub("[^A-Za-z0-9.-]";"-"))),name:$name,versionInfo:$evr,downloadLocation:"NOASSERTION",filesAnalyzed:false,checksums:[{algorithm:"SHA256",checksumValue:$checksum}]}]' <<<"$packages")"
done < <(find "$repo" -maxdepth 1 -type f -name '*.rpm' -print | sort)

jq -n --arg version "$version" --argjson packages "$packages" '{
  spdxVersion:"SPDX-2.3",
  dataLicense:"CC0-1.0",
  SPDXID:"SPDXRef-DOCUMENT",
  name:("Fedora-SL7-Remix-" + $version),
  documentNamespace:("https://github.com/B12Konsument/Fedora-SL-Remix/sbom/" + $version),
  creationInfo:{created:"2026-08-26T00:00:00Z",creators:["Tool: Fedora-SL7-Remix/create-sbom.sh"]},
  packages:$packages
}' > "$output"

