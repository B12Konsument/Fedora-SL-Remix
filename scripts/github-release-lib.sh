#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

readonly GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-B12Konsument/Fedora-SL-Remix}"

release_json() {
    local requested=${1:-latest}
    local api="https://api.github.com/repos/$GITHUB_REPOSITORY/releases"
    if [[ "$requested" == latest ]]; then
        curl --fail --silent --show-error --location "$api?per_page=50" | jq -e 'map(select(.draft == false)) | first'
    else
        curl --fail --silent --show-error --location "$api/tags/$requested"
    fi
}

download_asset() {
    local release=$1 pattern=$2 destination=$3
    local url name
    url="$(jq -er --arg pattern "$pattern" '.assets[] | select(.name | test($pattern)) | .browser_download_url' <<<"$release" | head -1)"
    name="$(basename "$url")"
    curl --fail --location --retry 3 --output "$destination/$name.partial" "$url"
    mv "$destination/$name.partial" "$destination/$name"
    printf '%s\n' "$destination/$name"
}

