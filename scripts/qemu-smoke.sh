#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

iso=${1:?usage: scripts/qemu-smoke.sh ISO [TIMEOUT_SECONDS]}
timeout_seconds=${2:-240}
[[ -f "$iso" ]] || die "ISO does not exist: $iso"
[[ "$timeout_seconds" =~ ^[0-9]+$ && $timeout_seconds -ge 30 ]] || die 'timeout must be at least 30 seconds'
require_command qemu-system-aarch64

firmware=/usr/share/edk2/aarch64/QEMU_EFI.fd
[[ -r "$firmware" ]] || die "QEMU AArch64 UEFI firmware is missing: $firmware"

work="$(mktemp -d /var/tmp/fedora-sl7-qemu.XXXXXX)"
log_file="$work/serial.log"
qemu_pid=
# This function is invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    find "$work" -depth -delete
}
trap cleanup EXIT

log 'Starting the AArch64 QEMU live-environment smoke test'
qemu-system-aarch64 \
    -machine virt,accel=tcg \
    -cpu max \
    -smp 4 \
    -m 4096 \
    -bios "$firmware" \
    -drive "file=$iso,media=cdrom,format=raw,readonly=on" \
    -boot d \
    -display none \
    -monitor none \
    -serial stdio \
    -no-reboot >"$log_file" 2>&1 &
qemu_pid=$!

deadline=$((SECONDS + timeout_seconds))
while ((SECONDS < deadline)); do
    if grep -q 'FEDORA_SL7_LIVE_READY' "$log_file"; then
        log 'QEMU reached the Fedora SL7 live userspace marker'
        exit 0
    fi
    if grep -Eqi 'Kernel panic|not syncing:|dracut Emergency Shell' "$log_file"; then
        tail -n 100 "$log_file" >&2
        die 'QEMU reported a boot failure before reaching live userspace'
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        wait "$qemu_pid" || true
        tail -n 100 "$log_file" >&2
        die 'QEMU exited before reaching live userspace'
    fi
    sleep 2
done

tail -n 100 "$log_file" >&2
die "QEMU did not reach live userspace within $timeout_seconds seconds"
