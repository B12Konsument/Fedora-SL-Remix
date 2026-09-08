# SPDX-License-Identifier: GPL-2.0-only
# shellcheck shell=bash

echo 'Configuring Fedora SL7 Remix integration'
systemctl enable sl7-kernel-default.service sl7-personalize-live.service sl7-qemu-smoke-marker.service sl7-wifi-mac.service

mkdir -p /boot/dtb/fedora-sl7-remix
# Match the patched kernel selected by KIWI. The stock recovery kernel also
# ships Romulus DTBs, but those do not describe the downstream QSPI touchpad.
mapfile -t sl7_kernels < <(find /boot -maxdepth 1 -type f -name 'vmlinuz-*.sl7.*' -print)
if [[ ${#sl7_kernels[@]} -ne 1 ]]; then
    echo 'Expected exactly one patched SL7 kernel for ISO DTB selection' >&2
    exit 1
fi
sl7_kernel=${sl7_kernels[0]}
sl7_kernel_version=${sl7_kernel##*/vmlinuz-}
romulus13="$(find "/usr/lib/modules/$sl7_kernel_version" -type f -name 'x1e80100-microsoft-romulus13.dtb' -print -quit)"
romulus15="$(find "/usr/lib/modules/$sl7_kernel_version" -type f -name 'x1e80100-microsoft-romulus15.dtb' -print -quit)"
test -n "$romulus13" -a -n "$romulus15"
cp "$romulus13" /boot/dtb/fedora-sl7-remix/romulus13.dtb
cp "$romulus15" /boot/dtb/fedora-sl7-remix/romulus15.dtb

if grep -q '^VARIANT=' /etc/os-release; then
    sed -i 's/^VARIANT=.*/VARIANT="SL7 Remix"/' /etc/os-release
else
    echo 'VARIANT="SL7 Remix"' >> /etc/os-release
fi
if grep -q '^VARIANT_ID=' /etc/os-release; then
    sed -i 's/^VARIANT_ID=.*/VARIANT_ID=sl7/' /etc/os-release
else
    echo 'VARIANT_ID=sl7' >> /etc/os-release
fi
echo 'IMAGE_ID=fedora-sl7-remix' >> /etc/os-release
