#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
source "$PROJECT_ROOT/scripts/lib.sh"

release=latest
bundle=
firmware_mode=auto
firmware_value=
force=0

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh [OPTIONS]

Install Fedora SL7 Remix hardware support onto an existing Fedora 44 AArch64
installation. Install Fedora with the official AArch64 media first and preserve
Windows unless you have another firmware-update and recovery plan.

Options:
  --release TAG             Install a specific GitHub release (default: latest).
  --bundle PATH             Use a local package bundle or RPM repository.
  --firmware auto           Extract from a mounted Windows volume when found (default).
  --firmware skip           Do not install proprietary firmware.
  --firmware download       Download and verify the pinned Microsoft MSI.
  --firmware-msi PATH       Extract a local copy of the pinned Microsoft MSI.
  --windows-root PATH       Extract from a mounted Windows system volume.
  --force-unsupported       Bypass Surface Laptop 7 detection for development.
  -h, --help                Show this help.

This tool never repartitions disks and never removes Windows.
EOF
}

while (($#)); do
    case "$1" in
        --release) release=${2:?--release requires a tag}; shift 2 ;;
        --bundle) bundle="$(realpath -- "${2:?--bundle requires a path}")"; shift 2 ;;
        --firmware) firmware_mode=${2:?--firmware requires auto, skip, or download}; shift 2 ;;
        --firmware-msi) firmware_mode=msi; firmware_value="$(realpath -- "${2:?--firmware-msi requires a path}")"; shift 2 ;;
        --windows-root) firmware_mode=windows; firmware_value="$(realpath -- "${2:?--windows-root requires a path}")"; shift 2 ;;
        --force-unsupported) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

((EUID == 0)) || die 'run the installer with sudo'
[[ "$(uname -m)" == aarch64 ]] || die 'the installer requires an AArch64 Fedora system'
require_command rpm
[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
source /etc/os-release
[[ ${ID:-} == fedora && ${VERSION_ID:-} == 44 ]] || die 'Fedora 44 is required by this release'

if ! "$PROJECT_ROOT/image/root/usr/bin/sl7-detect"; then
    ((force)) || die 'this device is not a supported Snapdragon Surface Laptop 7; use --force-unsupported only for development'
    warn 'hardware detection was bypassed'
fi

case "$firmware_mode" in auto|skip|download|msi|windows) ;; *) die "invalid firmware mode: $firmware_mode" ;; esac

temp="$(mktemp -d /var/tmp/fedora-sl7-install.XXXXXX)"
cleanup() {
    mountpoint -q "$temp/windows" 2>/dev/null && umount "$temp/windows"
    mountpoint -q "$temp/dislocker" 2>/dev/null && umount "$temp/dislocker"
    find "$temp" -depth -delete
}
trap cleanup EXIT

if [[ -z "$bundle" ]]; then
    log "Downloading package bundle for release $release"
    "$PROJECT_ROOT/scripts/download-package-bundle.sh" "$release" "$temp"
    bundle="$(find "$temp" -maxdepth 1 -type f -name '*packages*.tar.zst' -print -quit)"
fi

if [[ -d "$bundle" ]]; then
    repo_dir="$bundle"
else
    [[ -f "$bundle" ]] || die "package bundle does not exist: $bundle"
    repo_dir="$temp/repository"
    mkdir -p "$repo_dir"
    tar -C "$repo_dir" --zstd -xf "$bundle"
fi

mapfile -t rpms < <(find "$repo_dir" -type f -name '*.rpm' -print | sort)
((${#rpms[@]})) || die 'the package bundle contains no RPMs'

declare -a install_rpms=()
declare -A package_counts=()
declare -A sl7_kernel_counts=()
declare -A fallback_kernel_counts=()
for rpm_file in "${rpms[@]}"; do
    rpm_name="$(rpm -qp --queryformat '%{NAME}' "$rpm_file")"
    rpm_evr="$(rpm -qp --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$rpm_file")"
    case "$rpm_name" in
        fedora-sl7-remix-support|iptsd-sl7|qcom-firmware-extract|sl7-mac)
            install_rpms+=("$rpm_file")
            ((package_counts[$rpm_name] = ${package_counts[$rpm_name]:-0} + 1))
            ;;
        kernel-modules|kernel-modules-core|kernel-uki-dtbloader)
            install_rpms+=("$rpm_file")
            if [[ "$rpm_evr" == *'.sl7.'* ]]; then
                ((sl7_kernel_counts[$rpm_name] = ${sl7_kernel_counts[$rpm_name]:-0} + 1))
            else
                ((fallback_kernel_counts[$rpm_name] = ${fallback_kernel_counts[$rpm_name]:-0} + 1))
            fi
            ;;
    esac
done

for package in fedora-sl7-remix-support iptsd-sl7 qcom-firmware-extract sl7-mac; do
    [[ ${package_counts[$package]:-0} -eq 1 ]] || \
        die "the package bundle must contain exactly one $package RPM"
done
for package in kernel-modules kernel-modules-core kernel-uki-dtbloader; do
    [[ ${sl7_kernel_counts[$package]:-0} -eq 1 ]] || \
        die "the package bundle must contain exactly one SL7 $package RPM"
    [[ ${fallback_kernel_counts[$package]:-0} -eq 1 ]] || \
        die "the package bundle must contain exactly one Fedora fallback $package RPM"
done
[[ ${#install_rpms[@]} -eq 10 ]] || die 'the package bundle resolved to an unexpected install set'

log 'Installing the SL7 UKI, Fedora fallback UKI, and hardware integration packages'
dnf install -y "${install_rpms[@]}"
systemctl enable sl7-kernel-default.service sl7-wifi-mac.service

find_windows_root() {
    local candidate
    while IFS= read -r candidate; do
        [[ -d "$candidate/Windows/System32/DriverStore" ]] && { printf '%s\n' "$candidate"; return 0; }
    done < <(find /run/media /mnt /media -mindepth 1 -maxdepth 4 -type d 2>/dev/null || true)
    return 1
}

extract_from_unmounted_windows() {
    local device fstype mounted=0
    local mount_dir="$temp/windows" dislocker_dir="$temp/dislocker"
    mkdir -p "$mount_dir" "$dislocker_dir"
    while read -r device fstype; do
        mounted=0
        case "$fstype" in
            ntfs|ntfs3)
                mount -o ro "$device" "$mount_dir" 2>/dev/null && mounted=1
                ;;
            BitLocker)
                log "Unlocking $device read-only with dislocker; authentication may be requested"
                if dislocker --readonly "$device" -- "$dislocker_dir"; then
                    mount -o loop,ro "$dislocker_dir/dislocker-file" "$mount_dir" 2>/dev/null && mounted=1
                fi
                ;;
            *) continue ;;
        esac
        if ((mounted)) && [[ -d "$mount_dir/Windows/System32/DriverStore" ]]; then
            log "Extracting firmware from $device mounted read-only"
            sl7-firmware install --windows-root "$mount_dir"
            umount "$mount_dir"
            mountpoint -q "$dislocker_dir" 2>/dev/null && umount "$dislocker_dir"
            return 0
        fi
        ((mounted)) && umount "$mount_dir"
        mountpoint -q "$dislocker_dir" 2>/dev/null && umount "$dislocker_dir"
    done < <(lsblk -nrpo NAME,FSTYPE)
    return 1
}

case "$firmware_mode" in
    skip)
        warn 'proprietary firmware installation was skipped; GPU, audio, Wi-Fi, Bluetooth, or camera support may be incomplete'
        ;;
    download)
        sl7-firmware install --download
        ;;
    msi)
        sl7-firmware install --msi "$firmware_value"
        ;;
    windows)
        sl7-firmware install --windows-root "$firmware_value"
        ;;
    auto)
        if sl7-firmware status >/dev/null 2>&1; then
            log 'Required device firmware is already installed'
        elif windows_root="$(find_windows_root)"; then
            log "Extracting firmware from $windows_root"
            sl7-firmware install --windows-root "$windows_root"
        elif extract_from_unmounted_windows; then
            :
        else
            warn 'no mounted Windows system volume was found; run the Surface Laptop 7 Firmware assistant after reboot'
        fi
        ;;
esac

dracut --regenerate-all --force
/usr/libexec/sl7-set-default-kernel
mkdir -p /var/lib/fedora-sl7-remix
sl7-detect --json > /var/lib/fedora-sl7-remix/install.json || true

log 'Installation completed. Reboot into the Fedora SL7 Remix kernel.'
log 'Windows was not modified. Keep it for Surface firmware updates and recovery.'
