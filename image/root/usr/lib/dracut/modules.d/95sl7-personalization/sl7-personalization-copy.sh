#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only

sl7_payload=${SL7_PERSONALIZATION_ROOT:-/sl7-personalization}
[[ -d $sl7_payload ]] || return 0
[[ -n ${NEWROOT:-} && -d $NEWROOT ]] || {
    warn 'SL7 personalization payload exists, but the live root is unavailable'
    return 1
}

mkdir -p "$NEWROOT/run/sl7-personalization"
cp -a "$sl7_payload/." "$NEWROOT/run/sl7-personalization/" || return 1

# Populate the live overlay before switching roots and userspace coldplug.
# Firmware becoming available later does not retry a failed remoteproc probe.
mkdir -p "$NEWROOT/usr/lib/firmware/updates"
cp -a "$sl7_payload/firmware/." "$NEWROOT/usr/lib/firmware/updates/" || return 1
