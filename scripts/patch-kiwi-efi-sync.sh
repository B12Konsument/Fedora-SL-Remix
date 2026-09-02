#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command patch
require_command python3

kiwi_package="$(python3 -c 'import kiwi; print(kiwi.__path__[0])')"
kiwi_site_packages="$(dirname "$kiwi_package")"
patch_file="$PROJECT_ROOT/patches/kiwi/0001-do-not-copy-xattrs-into-fat-efi-image.patch"

[[ -f "$kiwi_package/bootloader/config/grub2.py" ]] || \
    die 'installed KIWI package does not contain the GRUB EFI implementation'

# This is an intentionally narrow runtime compatibility patch. It affects
# only KIWI's temporary copy into the FAT EFI image, where extended attributes
# cannot be stored. Refuse to continue if the pinned build environment changes
# and the audited context no longer applies.
if ! patch --dry-run --batch --fuzz=0 --directory="$kiwi_site_packages" --strip=1 < "$patch_file" >/dev/null; then
    printf '%s\n' 'KIWI EFI compatibility patch context:' >&2
    rpm -q kiwi-cli python3-kiwi 2>&1 >&2 || true
    grep -n -A12 -B4 'efi_data = DataSync' "$kiwi_package/bootloader/config/grub2.py" >&2 || true
    die 'KIWI EFI compatibility patch no longer applies; update and audit patches/kiwi/0001-do-not-copy-xattrs-into-fat-efi-image.patch'
fi
patch --batch --fuzz=0 --silent --directory="$kiwi_site_packages" --strip=1 < "$patch_file"

kernel_patch_file="$PROJECT_ROOT/patches/kiwi/0002-prefer-sl7-kernel.patch"
[[ -f "$kiwi_package/system/kernel.py" ]] || \
    die 'installed KIWI package does not contain the kernel lookup implementation'
if ! patch --dry-run --batch --fuzz=0 --directory="$kiwi_site_packages" --strip=1 < "$kernel_patch_file" >/dev/null; then
    printf '%s\n' 'KIWI kernel-selection patch context:' >&2
    rpm -q kiwi-cli python3-kiwi 2>&1 >&2 || true
    grep -n -A12 -B4 'kernel_entries = sorted' "$kiwi_package/system/kernel.py" >&2 || true
    die 'KIWI kernel-selection patch no longer applies; update and audit patches/kiwi/0002-prefer-sl7-kernel.patch'
fi
patch --batch --fuzz=0 --silent --directory="$kiwi_site_packages" --strip=1 < "$kernel_patch_file"
log 'Applied the KIWI EFI and Fedora SL7 kernel-selection compatibility patches'
