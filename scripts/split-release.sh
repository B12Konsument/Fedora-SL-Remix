#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
iso=${1:?ISO path required}
destination=${2:?destination required}
mkdir -p "$destination"
base="$(basename "$iso")"

if (( $(stat -c %s "$iso") > 1900 * 1024 * 1024 )); then
    split -b 1900M -d -a 3 "$iso" "$destination/$base.part-"
else
    cp "$iso" "$destination/$base"
fi

