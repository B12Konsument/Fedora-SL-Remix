#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
"$root/scripts/validate.sh"
"$root/tests/test-detect.sh"
"$root/tests/test-firmware-status.sh"
"$root/tests/test-release-split.sh"
