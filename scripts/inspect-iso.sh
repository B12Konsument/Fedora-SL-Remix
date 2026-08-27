#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command dtc
require_command rpm

iso=${1:?ISO path required}
mode=${2:---public}
[[ -f "$iso" ]] || die "ISO does not exist: $iso"
[[ "$mode" == --public || "$mode" == --private ]] || die 'mode must be --public or --private'

listing="$(xorriso -indev "$iso" -find / -type f -print 2>/dev/null)"
grep -Eqi '/EFI/BOOT/BOOTAA64[.]EFI$' <<<"$listing" || die 'ISO is missing EFI/BOOT/BOOTAA64.EFI'
grep -q '/LiveOS/' <<<"$listing" || die 'ISO is missing the LiveOS payload'

work="$(mktemp -d /var/tmp/sl7-iso-inspect.XXXXXX)"
mountpoint="$work/root"
trap 'mountpoint -q "$mountpoint" && umount "$mountpoint"; find "$work" -depth -delete' EXIT
xorriso -osirrox on -indev "$iso" -extract / "$work/iso" >/dev/null 2>&1
payload="$work/iso/LiveOS/squashfs.img"
[[ -f "$payload" ]] || die 'ISO has no LiveOS/squashfs.img'
mkdir -p "$work/squash" "$mountpoint"
unsquashfs -d "$work/squash" "$payload" >/dev/null

root="$work/squash"
rootfs="$(find "$work/squash" -type f -name 'rootfs.img' -print -quit)"
if [[ -n "$rootfs" ]]; then
    mount -o loop,ro "$rootfs" "$mountpoint"
    root="$mountpoint"
fi

[[ -x "$root/usr/bin/sl7-firmware" ]] || die 'live root is missing sl7-firmware'
[[ -x "$root/usr/bin/sl7-detect" ]] || die 'live root is missing sl7-detect'
romulus13="$(find "$root" -type f -name 'x1e80100-microsoft-romulus13.dtb' -print -quit)"
romulus15="$(find "$root" -type f -name 'x1e80100-microsoft-romulus15.dtb' -print -quit)"
[[ -n "$romulus13" ]] || die 'Romulus 13 DTB is missing'
[[ -n "$romulus15" ]] || die 'Romulus 15 DTB is missing'
dtc -q -I dtb -O dts "$romulus13" | grep -q 'microsoft,romulus13' || die 'Romulus 13 DTB has the wrong hardware identifier'
dtc -q -I dtb -O dts "$romulus15" | grep -q 'microsoft,romulus15' || die 'Romulus 15 DTB has the wrong hardware identifier'

rpm --root "$root" -q anaconda fedora-sl7-remix-support iptsd-sl7 sl7-mac \
    qcom-firmware-extract kernel-uki-dtbloader >/dev/null || die 'live root is missing a required RPM'
rpm --root "$root" -qa 'kernel*' | grep -q '[.]sl7[.]' || die 'live root is missing the Fedora SL7 kernel packages'

if [[ "$mode" == --public ]]; then
    if find "$work/iso" -type f -iname '*.msi' -print -quit | grep -q .; then
        die 'public ISO contains a Microsoft MSI'
    fi
    for forbidden in qcdxkmsuc8380.mbn qcadsp8380.mbn qccdsp8380.mbn adsp_dtbs.elf cdsp_dtbs.elf; do
        if find "$root/usr/lib/firmware" -type f -iname "$forbidden" -print -quit | grep -q .; then
            die "public ISO contains prohibited Microsoft firmware: $forbidden"
        fi
    done
fi

log "ISO inspection passed in ${mode#--} mode"
