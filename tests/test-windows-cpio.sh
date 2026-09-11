#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
pwsh_bin=${PWSH_BIN:-}
if [[ -z $pwsh_bin ]]; then
    pwsh_bin="$(command -v pwsh || true)"
fi
if [[ -z $pwsh_bin ]]; then
    if [[ ${REQUIRE_PWSH:-0} == 1 ]]; then
        printf 'pwsh is required for the Windows archive cross-check\n' >&2
        exit 1
    fi
    printf 'Windows CPIO cross-check skipped (pwsh is unavailable)\n'
    exit 0
fi
command -v cpio >/dev/null || { printf 'cpio is required for the Windows archive cross-check\n' >&2; exit 1; }

fixture="$(mktemp -d /tmp/sl7-windows-cpio.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT
archive="$fixture/personalization.cpio"
"$pwsh_bin" -NoLogo -NoProfile -File "$root/tests/windows/New-CpioFixture.ps1" "$archive"

mkdir "$fixture/extracted"
(
    cd "$fixture/extracted"
    cpio --quiet -id < "$archive"
)
while IFS= read -r -d '' payload; do
    relative=${payload#"$fixture/extracted/sl7-personalization/firmware/"}
    test -s "$payload"
    cmp "$payload" "$fixture/extracted/usr/lib/firmware/updates/$relative"
done < <(find "$fixture/extracted/sl7-personalization/firmware" -type f -print0)
[[ $(find "$fixture/extracted/usr/lib/firmware/updates" -type f | wc -l) -eq 10 ]]
grep -Fq 'synthetic-test-only' "$fixture/extracted/sl7-personalization/manifest.json"
printf 'Windows CPIO cross-check passed\n'
