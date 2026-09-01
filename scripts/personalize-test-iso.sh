#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

iso=${1:?base ISO required}
layout=${2:?personalization layout required}
output=${3:?output ISO required}
[[ -f $iso && -f $layout ]] || die 'base ISO or personalization layout is missing'
[[ "$(sha256sum "$iso" | cut -d' ' -f1)" == "$(jq -r '.base_iso.sha256' "$layout")" ]] || \
    die 'test personalization base hash mismatch'

cp --reflink=auto "$iso" "$output"
work="$(mktemp -d /var/tmp/sl7-qemu-personalization.XXXXXX)"
cleanup() {
    find "$work" -depth -delete
}
trap cleanup EXIT

selector="$work/model.cfg"
cat > "$selector" <<'EOF'
# FEDORA_SL7_MODEL_SLOT_V1
set sl7_personalized="1"
set sl7_model="QemuTest"
set sl7_model_label="CI smoke-test fixture"
set sl7_dtb=""
EOF
selector_size=$(jq -r '.slots.model_selector.length' "$layout")
selector_bytes=$(stat -c %s "$selector")
dd if=/dev/zero bs=1 count=$((selector_size - selector_bytes)) status=none | tr '\0' ' ' >> "$selector"
selector_offset=$(jq -r '.slots.model_selector.offset' "$layout")
dd if="$selector" of="$output" bs=1 seek="$selector_offset" conv=notrunc status=none

log "Created synthetic QEMU-personalized ISO: $output"
