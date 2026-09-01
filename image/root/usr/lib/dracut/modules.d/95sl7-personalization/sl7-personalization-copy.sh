#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only

[[ -d /sl7-personalization ]] || return 0
[[ -n ${NEWROOT:-} && -d $NEWROOT ]] || {
    warn 'SL7 personalization payload exists, but the live root is unavailable'
    return 1
}

mkdir -p "$NEWROOT/run/sl7-personalization"
cp -a /sl7-personalization/. "$NEWROOT/run/sl7-personalization/"
