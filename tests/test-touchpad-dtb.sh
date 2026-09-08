#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
command -v dtc >/dev/null || { echo 'dtc is required for touchpad DTB tests' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

cat > "$work/valid.dts" <<'EOF'
/dts-v1/;
/ {
    pins { active: active {}; reset: reset {}; };
    controller {
        compatible = "qcom,geni-spi-qspi";
        status = "okay";
        touchpad {
            compatible = "hid-over-spi";
            pinctrl-names = "active", "reset";
            pinctrl-0 = <&active>;
            pinctrl-1 = <&reset>;
        };
    };
};
EOF
dtc -q -I dts -O dtb -o "$work/valid.dtb" "$work/valid.dts"
python3 "$root/scripts/check-touchpad-dtb.py" "$work/valid.dtb"

# Reject the stock controller binding, a disabled ancestor, and the old GPIO
# reset contract. Model identifiers alone would accept all three cases.
for mutation in \
    's/qcom,geni-spi-qspi/qcom,geni-spi/' \
    's/status = "okay"/status = "disabled"/' \
    's/"active", "reset"/"default", "sleep"/' \
    '/pinctrl-1 =/d'; do
    sed "$mutation" "$work/valid.dts" > "$work/invalid.dts"
    dtc -q -I dts -O dtb -o "$work/invalid.dtb" "$work/invalid.dts"
    if python3 "$root/scripts/check-touchpad-dtb.py" "$work/invalid.dtb" >"$work/result" 2>&1; then
        echo "Touchpad DTB check accepted invalid fixture: $mutation" >&2
        exit 1
    fi
done
echo 'Touchpad DTB tests passed'
