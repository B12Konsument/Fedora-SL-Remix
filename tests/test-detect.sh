#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /tmp/sl7-detect-test.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT
mkdir -p "$fixture/sys/class/dmi/id" "$fixture/sys/firmware/devicetree/base"

printf 'Surface_Laptop_7th_Edition_2036' > "$fixture/sys/class/dmi/id/product_sku"
printf 'Microsoft Surface Laptop' > "$fixture/sys/class/dmi/id/product_name"
result="$(SL7_SYS_ROOT="$fixture" "$root/image/root/usr/bin/sl7-detect" --json)"
jq -e '.supported == true and .model == "romulus13" and .display_inches == "13.8"' <<<"$result" >/dev/null

printf 'Surface_Laptop_7th_Edition_2038_Intel' > "$fixture/sys/class/dmi/id/product_sku"
if SL7_SYS_ROOT="$fixture" "$root/image/root/usr/bin/sl7-detect" >/dev/null; then
    printf 'an Intel/x86_64 SKU was incorrectly accepted\n' >&2
    exit 1
fi

printf 'Surface_Laptop_7th_Edition_2037' > "$fixture/sys/class/dmi/id/product_sku"
result="$(SL7_SYS_ROOT="$fixture" "$root/image/root/usr/bin/sl7-detect" --json)"
jq -e '.supported == true and .model == "romulus15" and .display_inches == "15"' <<<"$result" >/dev/null

printf 'Unsupported_Device' > "$fixture/sys/class/dmi/id/product_sku"
printf 'microsoft,romulus13\0qcom,x1e80100\0' > "$fixture/sys/firmware/devicetree/base/compatible"
result="$(SL7_SYS_ROOT="$fixture" "$root/image/root/usr/bin/sl7-detect" --json)"
jq -e '.supported == true and .model == "romulus13"' <<<"$result" >/dev/null

printf 'unrelated,device\0' > "$fixture/sys/firmware/devicetree/base/compatible"
if SL7_SYS_ROOT="$fixture" "$root/image/root/usr/bin/sl7-detect" >/dev/null; then
    printf 'unsupported hardware was accepted\n' >&2
    exit 1
fi

printf 'hardware detection tests passed\n'
