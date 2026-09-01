#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
include_container=0
[[ ${1:-} == --include-container ]] && include_container=1
[[ $# -le 1 ]] || { printf 'Usage: sudo ./scripts/clean.sh [--include-container]\n' >&2; exit 2; }

if ((EUID != 0)); then
    exec sudo -- "$0" "$@"
fi

for relative in .build out .local/state; do
    target="$PROJECT_ROOT/$relative"
    resolved_parent="$(realpath -m -- "$(dirname -- "$target")")"
    [[ $resolved_parent == "$PROJECT_ROOT" || $resolved_parent == "$PROJECT_ROOT/.local" ]] || {
        printf 'Refusing unexpected cleanup target: %s\n' "$target" >&2
        exit 1
    }
    if [[ -d $target ]]; then
        find "$target" -xdev -depth -mindepth 1 -delete
        rmdir -- "$target"
    fi
done

if ((include_container)); then
    if podman image exists localhost/fedora-sl7-remix-builder:latest; then
        podman image rm localhost/fedora-sl7-remix-builder:latest
    fi
fi

printf 'Removed generated Fedora SL7 Remix build artifacts.\n'
