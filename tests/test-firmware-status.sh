#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /tmp/sl7-firmware-test.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT

if SL7_FIRMWARE_ROOT="$fixture" "$root/image/root/usr/bin/sl7-firmware" status >/dev/null; then
    printf 'an empty firmware directory was reported as complete\n' >&2
    exit 1
fi

mkdir -p "$fixture/Romulus"
printf 'fixture\n' > "$fixture/qcdxkmsuc8380.mbn"
for name in \
    adsp_dtbs.elf adspr.jsn adsps.jsn adspua.jsn battmgr.jsn \
    cdsp_dtbs.elf cdspr.jsn qcadsp8380.mbn qccdsp8380.mbn; do
    printf 'fixture\n' > "$fixture/Romulus/$name"
done

SL7_FIRMWARE_ROOT="$fixture" "$root/image/root/usr/bin/sl7-firmware" status >/dev/null
printf 'firmware status tests passed\n'

