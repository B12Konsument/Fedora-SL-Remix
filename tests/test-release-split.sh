#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /tmp/sl7-release-test.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT

printf 'test ISO payload\n' > "$fixture/test.iso"
"$root/scripts/split-release.sh" "$fixture/test.iso" "$fixture/assets"
cmp "$fixture/test.iso" "$fixture/assets/test.iso"
printf 'release split test passed\n'

