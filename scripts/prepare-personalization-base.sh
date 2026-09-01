#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command cpio
require_command dd
require_command od
require_command sha256sum
require_command truncate
require_command xorriso

input=${1:?input ISO required}
output=${2:?output ISO required}
[[ -f "$input" ]] || die "input ISO does not exist: $input"
[[ "$input" != "$output" ]] || die 'input and output ISO paths must differ'

readonly selector_size=4096
readonly payload_size=$((256 * 1024 * 1024))
work="$(mktemp -d /var/tmp/sl7-personalization-base.XXXXXX)"
cleanup() {
    find "$work" -depth -delete
}
trap cleanup EXIT

selector="$work/model.cfg"
cp "$PROJECT_ROOT/image/model-selector.placeholder.cfg" "$selector"
selector_bytes=$(stat -c %s "$selector")
((selector_bytes < selector_size)) || die 'model-selector placeholder exceeds its reserved size'
dd if=/dev/zero bs=1 count=$((selector_size - selector_bytes)) status=none | tr '\0' ' ' >> "$selector"
[[ $(stat -c %s "$selector") -eq $selector_size ]] || die 'could not create the model-selector slot'

mkdir -p "$work/empty"
payload="$work/personalization.cpio"
(
    cd "$work/empty"
    printf '' | cpio --quiet -o --format=newc > "$payload"
)
payload_bytes=$(stat -c %s "$payload")
((payload_bytes < payload_size)) || die 'empty CPIO unexpectedly exceeds its reserved size'
truncate -s "$payload_size" "$payload"

image_root="$BUILD_ROOT/kiwi-output/result-build/build/image-root"
if [[ ! -d "$image_root" ]]; then
    image_root="$(find "$BUILD_ROOT/kiwi-output" -type d -path '*/build/image-root' -print -quit)"
fi
[[ -n "$image_root" && -d "$image_root" ]] || die 'could not locate the KIWI image root'
romulus13="$(find "$image_root/usr/lib/modules" -type f -name 'x1e80100-microsoft-romulus13.dtb' -print -quit)"
romulus15="$(find "$image_root/usr/lib/modules" -type f -name 'x1e80100-microsoft-romulus15.dtb' -print -quit)"
[[ -n "$romulus13" && -n "$romulus15" ]] || die 'could not locate both Romulus DTBs in the KIWI image root'

log 'Adding fixed personalization slots and both Romulus DTBs to the ISO'
xorriso \
    -indev "$input" \
    -outdev "$output" \
    -boot_image any replay \
    -map "$selector" /boot/sl7/model.cfg \
    -map "$payload" /boot/sl7/personalization.cpio \
    -map "$romulus13" /boot/dtb/fedora-sl7-remix/romulus13.dtb \
    -map "$romulus15" /boot/dtb/fedora-sl7-remix/romulus15.dtb \
    -commit_eject all >/dev/null

# xorriso can leave output-device padding beyond the ISO volume and the replayed
# backup GPT. Trim only that padding, using the primary volume descriptor as the
# authoritative hybrid-image length.
volume_blocks="$(od -An -tu4 -j $((16 * 2048 + 80)) -N4 "$output" | tr -d ' ')"
[[ $volume_blocks =~ ^[1-9][0-9]*$ ]] || die 'could not read the rebuilt ISO volume size'
volume_bytes=$((volume_blocks * 2048))
actual_bytes=$(stat -c %s "$output")
((actual_bytes >= volume_bytes)) || die 'rebuilt ISO is shorter than its declared volume size'
truncate -s "$volume_bytes" "$output"

# Personalization changes bytes inside the declared ISO volume. Clear the
# isomd5 application-data field so the finished image never advertises a stale
# embedded checksum. Release and personalized images use SHA-256 instead.
dd if=/dev/zero of="$output" bs=1 seek=$((16 * 2048 + 883)) count=512 conv=notrunc status=none

[[ -s "$output" ]] || die 'personalization-base ISO creation produced no output'
log "Created personalization-base ISO: $output"
