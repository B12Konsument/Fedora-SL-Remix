#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command jq
require_command sha256sum
require_command xorriso

iso=${1:?base ISO required}
output=${2:?output JSON required}
[[ -f "$iso" ]] || die "base ISO does not exist: $iso"

slot_json() {
    local iso_path=$1 expected_size=$2 placeholder=$3 report count lba blocks
    report="$(xorriso -indev "$iso" -find "$iso_path" -exec report_lba -- 2>&1 | grep -F "'$iso_path'")"
    count=$(grep -Fc "'$iso_path'" <<<"$report")
    [[ $count -eq 1 ]] || die "slot does not have exactly one ISO extent: $iso_path"
    lba=$(awk -F, '{gsub(/ /, "", $2); print $2}' <<<"$report")
    blocks=$(awk -F, '{gsub(/ /, "", $3); print $3}' <<<"$report")
    [[ "$lba" =~ ^[0-9]+$ && "$blocks" =~ ^[0-9]+$ ]] || die "could not parse ISO extent for $iso_path"
    ((blocks * 2048 >= expected_size)) || die "ISO extent is too small for $iso_path"
    jq -n \
        --arg path "$iso_path" \
        --argjson offset "$((lba * 2048))" \
        --argjson length "$expected_size" \
        --arg sha256 "$(sha256sum "$placeholder" | cut -d' ' -f1)" \
        '{path:$path,offset:$offset,length:$length,placeholder_sha256:$sha256}'
}

work="$(mktemp -d /var/tmp/sl7-layout.XXXXXX)"
cleanup() {
    find "$work" -depth -delete
}
trap cleanup EXIT
xorriso -osirrox on -indev "$iso" \
    -extract /boot/sl7/model.cfg "$work/model.cfg" \
    -extract /boot/sl7/personalization.cpio "$work/personalization.cpio" >/dev/null 2>&1

selector="$(slot_json /boot/sl7/model.cfg 4096 "$work/model.cfg")"
payload="$(slot_json /boot/sl7/personalization.cpio $((256 * 1024 * 1024)) "$work/personalization.cpio")"
msi="$(jq -c '.sources[] | select(.id == "surface-laptop-7-msi") | {filename,version,url,size,sha256}' "$SOURCE_LOCK")"

jq -n \
    --arg version "$(<"$PROJECT_ROOT/VERSION")" \
    --arg iso_name "$(basename "$iso")" \
    --arg iso_sha256 "$(sha256sum "$iso" | cut -d' ' -f1)" \
    --argjson iso_size "$(stat -c %s "$iso")" \
    --arg source_lock_sha256 "$(sha256sum "$SOURCE_LOCK" | cut -d' ' -f1)" \
    --argjson selector "$selector" \
    --argjson payload "$payload" \
    --argjson msi "$msi" \
    '{
      schema:1,
      minimum_customizer_version:"0.2.1",
      fedora_release:44,
      remix_version:$version,
      source_lock_sha256:$source_lock_sha256,
      base_iso:{name:$iso_name,size:$iso_size,sha256:$iso_sha256,parts:[]},
      slots:{model_selector:$selector,personalization:$payload},
      hardware:{
        Surface_Laptop_7th_Edition_2036:{model:"Romulus13",dtb:"/boot/dtb/fedora-sl7-remix/romulus13.dtb",display_inches:"13.8"},
        Surface_Laptop_7th_Edition_2037:{model:"Romulus15",dtb:"/boot/dtb/fedora-sl7-remix/romulus15.dtb",display_inches:"15"}
      },
      microsoft_msi:$msi,
      windows_bundle:null
    }' > "$output"

jq -e '.schema == 1 and .slots.model_selector.length == 4096 and .slots.personalization.length == 268435456' "$output" >/dev/null
log "Created personalization layout: $output"
