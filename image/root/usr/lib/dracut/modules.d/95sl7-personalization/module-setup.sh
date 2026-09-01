#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only

check() {
    return 0
}

depends() {
    return 0
}

install() {
    # dracut defines moddir before loading this module.
    # shellcheck disable=SC2154
    inst_hook pre-pivot 95 "$moddir/sl7-personalization-copy.sh"
}
