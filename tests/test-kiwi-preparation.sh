#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
project="$work/project"
mkdir -p "$project/scripts" "$project/image"
cp "$root/scripts/"{lib,prepare-kiwi}.sh "$project/scripts/"
cp "$root/image/"{sl7.xml,grub-arm.cfg.iso-template} "$project/image/"
printf 'echo sl7-integration-ran\n' > "$project/image/config-sl7.sh"
source_dir="$work/build/sources/fedora-kiwi-descriptions"
mkdir -p "$source_dir/"{.git,components,repositories}
printf '<image/>\n' > "$source_dir/Fedora.kiwi"
printf '<image/>\n' > "$source_dir/components/liveinstall.xml"
# Match the pinned upstream script's terminal exit and trailing blank line.
printf '#!/bin/bash\necho upstream-ran\nexit 0\n\n' > "$source_dir/config.sh"
BUILD_ROOT="$work/build" bash "$project/scripts/prepare-kiwi.sh"
actual=$(bash "$work/build/kiwi/config.sh")
[[ $actual == $'upstream-ran\nsl7-integration-ran' ]] || {
    echo 'SL7 integration is unreachable in the generated KIWI config.sh' >&2
    exit 1
}

# An upstream layout change needs review instead of another blind append.
printf '#!/bin/bash\necho upstream-ran\n' > "$source_dir/config.sh"
if BUILD_ROOT="$work/build" bash "$project/scripts/prepare-kiwi.sh" >"$work/error" 2>&1; then
    echo 'KIWI preparation accepted an unexpected upstream config layout' >&2
    exit 1
fi
grep -Fq 'no longer ends with exit 0' "$work/error"
echo 'KIWI integration preparation tests passed'
