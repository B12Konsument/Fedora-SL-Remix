#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
image_root="$work/build/kiwi-output/result-build/build/image-root"
stock="$image_root/usr/lib/modules/7.1.10-200.fc44.aarch64/dtb/qcom"
patched="$image_root/usr/lib/modules/7.1.10-200.sl7.2.fc44.aarch64/dtb/qcom"
staged="$image_root/boot/dtb/fedora-sl7-remix"
# Create the recovery kernel first, reproducing the release's traversal order.
mkdir -p "$stock" "$patched" "$staged" "$work/input"
touch "$image_root/boot/vmlinuz-7.1.10-200.fc44.aarch64"
touch "$image_root/boot/vmlinuz-7.1.10-200.sl7.2.fc44.aarch64"
for model in 13 15; do
    cat > "$work/model.dts" <<EOF
/dts-v1/;
/ {
    compatible = "microsoft,romulus$model";
    pins { active: active {}; reset: reset {}; };
    controller {
        compatible = "qcom,geni-spi-qspi";
        touchpad {
            compatible = "hid-over-spi";
            pinctrl-names = "active", "reset";
            pinctrl-0 = <&active>;
            pinctrl-1 = <&reset>;
        };
    };
};
EOF
    dtc -q -I dts -O dtb -o "$patched/x1e80100-microsoft-romulus$model.dtb" "$work/model.dts"
    cp "$patched/x1e80100-microsoft-romulus$model.dtb" "$staged/romulus$model.dtb"
    printf '/dts-v1/; / { compatible = "microsoft,romulus%s"; };\n' "$model" > "$work/stock.dts"
    dtc -q -I dts -O dtb -o "$stock/x1e80100-microsoft-romulus$model.dtb" "$work/stock.dts"
done
printf 'synthetic ISO\n' > "$work/input/fixture.txt"
xorriso -as mkisofs -quiet -o "$work/input.iso" "$work/input" >"$work/xorriso.log" 2>&1
BUILD_ROOT="$work/build" "$root/scripts/prepare-personalization-base.sh" \
    "$work/input.iso" "$work/output.iso" >"$work/prepare.log" 2>&1 || {
    cat "$work/prepare.log" >&2
    exit 1
}
xorriso -osirrox on -indev "$work/output.iso" \
    -extract /boot/dtb/fedora-sl7-remix "$work/extracted" >"$work/extract.log" 2>&1
for model in 13 15; do
    cmp "$patched/x1e80100-microsoft-romulus$model.dtb" "$work/extracted/romulus$model.dtb"
    python3 "$root/scripts/check-touchpad-dtb.py" "$work/extracted/romulus$model.dtb"
done

expect_failure() {
    local message=$1
    if BUILD_ROOT="$work/build" "$root/scripts/prepare-personalization-base.sh" \
        "$work/input.iso" "$work/rejected.iso" >"$work/error" 2>&1; then
        echo "ISO preparation unexpectedly succeeded: $message" >&2
        exit 1
    fi
    grep -Fq "$message" "$work/error"
    [[ ! -e "$work/rejected.iso" ]] || { echo 'Invalid DTBs reached ISO writing' >&2; exit 1; }
}

cp "$stock/x1e80100-microsoft-romulus13.dtb" "$staged/romulus13.dtb"
expect_failure 'does not match the patched SL7 kernel'
cp "$patched/x1e80100-microsoft-romulus13.dtb" "$staged/romulus13.dtb"
rm "$staged/romulus15.dtb"
expect_failure 'staged Romulus 15 DTB is missing'
cp "$patched/x1e80100-microsoft-romulus15.dtb" "$staged/romulus15.dtb"
touch "$image_root/boot/vmlinuz-7.1.10-200.sl7.1.fc44.aarch64"
expect_failure 'expected exactly one patched SL7 kernel'
rm "$image_root/boot/vmlinuz-7.1.10-200.sl7.1.fc44.aarch64"
cp "$stock/x1e80100-microsoft-romulus13.dtb" "$patched/x1e80100-microsoft-romulus13.dtb"
cp "$stock/x1e80100-microsoft-romulus13.dtb" "$staged/romulus13.dtb"
expect_failure 'expected one enabled Romulus QSPI touchpad'
echo 'Personalization-base ISO DTB tests passed'
