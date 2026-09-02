#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command dtc
require_command jq
require_command losetup
require_command lsinitrd
require_command mount
require_command mountpoint
require_command mknod
require_command rpm
require_command umount

iso=${1:?ISO path required}
mode=${2:---base}
[[ -f "$iso" ]] || die "ISO does not exist: $iso"
[[ "$mode" == --base ]] || die 'mode must be --base'

# A privileged Podman container can access the host loop driver, but its
# private /dev may initially contain only /dev/loop0.  Create a small, explicit
# set of ephemeral device nodes for the three nested read-only mounts below.
for loop_index in {0..7}; do
    loop_device="/dev/loop$loop_index"
    if [[ ! -b "$loop_device" ]]; then
        mknod -m 0660 "$loop_device" b 7 "$loop_index"
    fi
done
losetup -f >/dev/null || die 'no free loop device is available for ISO inspection'

work="$(mktemp -d /var/tmp/sl7-iso-inspect.XXXXXX)"
iso_mount="$work/iso"
squash_mount="$work/squash"
root_mount="$work/root"
cleanup() {
    local point
    local cleanup_ok=1
    for point in "$root_mount" "$squash_mount" "$iso_mount"; do
        if mountpoint -q "$point"; then
            umount "$point" || cleanup_ok=0
        fi
    done
    if ((cleanup_ok)); then
        find "$work" -depth -delete
    else
        warn "could not unmount every inspection filesystem below $work"
    fi
}
trap cleanup EXIT
mkdir -p "$iso_mount" "$squash_mount" "$root_mount"

log 'Inspecting the ISO through read-only loop mounts'
mount -o loop,ro "$iso" "$iso_mount"
[[ -f "$iso_mount/EFI/BOOT/BOOTAA64.EFI" ]] || die 'ISO is missing EFI/BOOT/BOOTAA64.EFI'
[[ -f "$iso_mount/boot/sl7/model.cfg" ]] || die 'ISO is missing the model-selector slot'
[[ $(stat -c %s "$iso_mount/boot/sl7/model.cfg") -eq 4096 ]] || die 'model-selector slot has the wrong size'
[[ -f "$iso_mount/boot/sl7/personalization.cpio" ]] || die 'ISO is missing the personalization slot'
[[ $(stat -c %s "$iso_mount/boot/sl7/personalization.cpio") -eq $((256 * 1024 * 1024)) ]] || \
    die 'personalization slot has the wrong size'
grep -Fq 'sl7_personalized="0"' "$iso_mount/boot/sl7/model.cfg" || \
    die 'the base model-selector does not fail closed'
grep -Fq 'Personalize this base image from Windows before booting' "$iso_mount/boot/grub2/grub.cfg" || \
    die 'GRUB is missing the unpersonalized-image guard'
if grep -Fq 'rd.live.check' "$iso_mount/boot/grub2/grub.cfg"; then
    die 'the mutable personalization base must not advertise an embedded media check'
fi
payload="$iso_mount/LiveOS/squashfs.img"
[[ -f "$payload" ]] || die 'ISO has no LiveOS/squashfs.img'
# Fedora keeps the historical LiveOS/squashfs.img filename while Fedora 44's
# KIWI LiveInstall profile stores an EROFS filesystem in that file.
mount -t erofs -o loop,ro "$payload" "$squash_mount"

root="$squash_mount"
rootfs="$(find "$squash_mount" -type f -name 'rootfs.img' -print -quit)"
if [[ -n "$rootfs" ]]; then
    mount -o loop,ro "$rootfs" "$root_mount"
    root="$root_mount"
fi

[[ -x "$root/usr/bin/sl7-firmware" ]] || die 'live root is missing sl7-firmware'
[[ -x "$root/usr/bin/sl7-detect" ]] || die 'live root is missing sl7-detect'
[[ -x "$root/usr/libexec/sl7-apply-personalization" ]] || die 'live root is missing the personalization installer'
[[ -f "$root/usr/share/anaconda/post-scripts/95-sl7-personalization.ks" ]] || \
    die 'live root is missing the Anaconda personalization handoff'
[[ -x "$root/usr/bin/anaconda" ]] || die 'live root is missing the Anaconda installer'
romulus13="$iso_mount/boot/dtb/fedora-sl7-remix/romulus13.dtb"
romulus15="$iso_mount/boot/dtb/fedora-sl7-remix/romulus15.dtb"
[[ -f "$romulus13" ]] || die 'Romulus 13 DTB is missing'
[[ -f "$romulus15" ]] || die 'Romulus 15 DTB is missing'
romulus13_dts="$work/romulus13.dts"
romulus15_dts="$work/romulus15.dts"
dtc -q -I dtb -O dts -o "$romulus13_dts" "$romulus13" || die 'Romulus 13 DTB is malformed'
dtc -q -I dtb -O dts -o "$romulus15_dts" "$romulus15" || die 'Romulus 15 DTB is malformed'
grep -Fq 'microsoft,romulus13' "$romulus13_dts" || die 'Romulus 13 DTB has the wrong hardware identifier'
grep -Fq 'microsoft,romulus15' "$romulus15_dts" || die 'Romulus 15 DTB has the wrong hardware identifier'

rpm --root "$root" -q anaconda-install-env-deps anaconda-live \
    fedora-sl7-remix-support iptsd-sl7 sl7-mac \
    kernel-uki-dtbloader >/dev/null || die 'live root is missing a required RPM'
kernel_packages="$work/kernel-packages.txt"
rpm --root "$root" -qa 'kernel*' > "$kernel_packages" || die 'could not query the live root kernel packages'
grep -q '[.]sl7[.]' "$kernel_packages" || die 'live root is missing the Fedora SL7 kernel packages'
stock_kernel_evr="$(jq -er '.sources[] | select(.id == "fedora-kernel-distgit") | .version + "-" + .release' "$SOURCE_LOCK")"
rpm --root "$root" -q "kernel-uki-dtbloader-$stock_kernel_evr.aarch64" >/dev/null || \
    die 'live root is missing the unmodified Fedora fallback kernel'

initrd_scan="$work/initrds"
mkdir "$initrd_scan"
initrd_index=0
while IFS= read -r -d '' initrd; do
    initrd_index=$((initrd_index + 1))
    initrd_root="$initrd_scan/$initrd_index"
    mkdir "$initrd_root"
    (
        cd "$initrd_root"
        lsinitrd --unpack "$initrd" >/dev/null
    ) || die "could not inspect initramfs content: $initrd"
done < <(find "$iso_mount" -xdev -type f \( -iname 'initrd' -o -iname 'initrd.img' -o -iname 'initrd-*.img' \) -print0)
((initrd_index > 0)) || die 'ISO is missing a boot initramfs'

denylist="$PROJECT_ROOT/firmware/prohibited-content-hashes.json"
"$PROJECT_ROOT/scripts/check-prohibited-content.sh" "$denylist" "$root" \
    "$iso_mount" "$root" "$initrd_scan"

log 'Personalization-base ISO inspection passed'
