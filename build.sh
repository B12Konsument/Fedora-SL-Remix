#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT
readonly IMAGE_NAME="fedora-sl7-remix-builder"
readonly MIN_FREE_GIB="${MIN_FREE_GIB:-80}"

firmware_mode=redistributable
firmware_source=
output_dir="$PROJECT_ROOT/out"
clean=0

usage() {
    cat <<'EOF'
Usage: sudo ./build.sh [OPTIONS]

Build the Fedora SL7 Remix AArch64 ISO.

Options:
  --with-microsoft-firmware  Download, verify, and embed the pinned Microsoft MSI firmware.
  --firmware-source PATH     Verify and extract firmware from a local copy of the pinned MSI.
  --output DIR               Write final artifacts to DIR (default: ./out).
  --clean                    Remove the project's build cache before building.
  -h, --help                 Show this help.

The default image is redistribution-safe. Images containing Microsoft firmware
are for personal use and must not be redistributed.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --with-microsoft-firmware)
            [[ -z "$firmware_source" ]] || die '--with-microsoft-firmware and --firmware-source are mutually exclusive'
            firmware_mode=download
            shift
            ;;
        --firmware-source)
            (($# >= 2)) || die '--firmware-source requires a path'
            [[ "$firmware_mode" == redistributable ]] || die '--with-microsoft-firmware and --firmware-source are mutually exclusive'
            firmware_mode=local
            firmware_source="$(realpath -- "$2")"
            [[ -f "$firmware_source" ]] || die "firmware source does not exist: $firmware_source"
            shift 2
            ;;
        --output)
            (($# >= 2)) || die '--output requires a directory'
            output_dir="$(realpath -m -- "$2")"
            shift 2
            ;;
        --clean)
            clean=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$(uname -s)" == Linux ]] || die 'the builder requires Linux; use a Fedora AArch64 virtual machine'
command -v podman >/dev/null || die 'Podman is required (Fedora: sudo dnf install podman)'
command -v realpath >/dev/null || die 'realpath from GNU coreutils is required'

host_arch="$(uname -m)"
case "$host_arch" in
    aarch64|arm64) platform_args=() ;;
    x86_64|amd64)
        platform_args=(--arch arm64)
        printf 'warning: x86_64 builds use AArch64 emulation and can take many hours.\n' >&2
        [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] || die 'AArch64 binfmt is not registered; install and enable qemu-user-static first'
        ;;
    *) die "unsupported host architecture: $host_arch" ;;
esac

((EUID == 0)) || die 'the KIWI container needs root for loop devices and mounts; run this command with sudo'

available_kib="$(df -Pk "$PROJECT_ROOT" | awk 'NR==2 {print $4}')"
required_kib=$((MIN_FREE_GIB * 1024 * 1024))
((available_kib >= required_kib)) || die "at least ${MIN_FREE_GIB} GiB free space is required"

if ((clean)); then
    build_cache="$PROJECT_ROOT/.build"
    [[ "$build_cache" == "$PROJECT_ROOT/.build" ]] || die 'refusing to clean an unexpected path'
    find "$build_cache" -depth -mindepth 1 -delete 2>/dev/null || true
fi

mkdir -p -- "$PROJECT_ROOT/.build" "$output_dir"
podman build "${platform_args[@]}" --tag "$IMAGE_NAME" --file "$PROJECT_ROOT/build/Containerfile" "$PROJECT_ROOT/build"

container_args=(
    run --rm --privileged --security-opt label=disable
    "${platform_args[@]}"
    --env "FIRMWARE_MODE=$firmware_mode"
    --env "BUILD_VERSION=$(<"$PROJECT_ROOT/VERSION")"
    --volume "$PROJECT_ROOT:/workspace"
    --volume "$output_dir:/output"
)

if [[ -n "$firmware_source" ]]; then
    container_args+=(--env FIRMWARE_SOURCE=/run/firmware/SurfaceLaptop7.msi)
    container_args+=(--volume "$firmware_source:/run/firmware/SurfaceLaptop7.msi:ro")
fi

podman "${container_args[@]}" "$IMAGE_NAME"
printf 'Build artifacts are available in %s\n' "$output_dir"
