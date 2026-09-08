#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check the Romulus DT contract required by the pinned QSPI HID driver."""

import subprocess
import sys


def check(dtb):
    def get(node, prop):
        result = subprocess.run(
            ["fdtget", "-t", "s", dtb, node, prop],
            capture_output=True, text=True, check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else ""

    def children(node):
        result = subprocess.run(
            ["fdtget", "-l", dtb, node],
            capture_output=True, text=True, check=True,
        )
        for name in result.stdout.split():
            yield node.rstrip("/") + "/" + name

    def walk(node, enabled=True):
        enabled = enabled and get(node, "status") in ("", "ok", "okay")
        if "hid-over-spi" in get(node, "compatible").split():
            parent = node.rsplit("/", 1)[0] or "/"
            if "qcom,geni-spi-qspi" in get(parent, "compatible").split():
                if not enabled:
                    raise ValueError("QSPI touchpad or its controller is disabled")
                names = get(node, "pinctrl-names").split()
                if not {"active", "reset"}.issubset(names):
                    raise ValueError("QSPI touchpad needs active and reset pinctrl states")
                for name in ("active", "reset"):
                    subprocess.run(
                        ["fdtget", "-t", "x", dtb, node,
                         f"pinctrl-{names.index(name)}"],
                        stdout=subprocess.DEVNULL, check=True,
                    )
                yield node
        for child in children(node):
            yield from walk(child, enabled)

    if len(list(walk("/"))) != 1:
        raise ValueError("expected one enabled Romulus QSPI touchpad")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: check-touchpad-dtb.py DTB")
    try:
        check(sys.argv[1])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Touchpad DTB check failed: {error}")
