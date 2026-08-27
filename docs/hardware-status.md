# Hardware status

Status terms are deliberately strict:

- `CI-tested`: verified structurally or in QEMU, not on Surface hardware.
- `hardware-verified`: passed the repository checklist on the reference device.
- `community-verified`: passed on hardware reported by another contributor.
- `untested`: support exists but no accepted physical test is recorded.
- `known broken`: a known implementation gap prevents normal use.

## Device coverage

| Model | Selector | Status |
| --- | --- | --- |
| 13.8-inch consumer, SKU 2036 | Romulus 13 DTB | untested |
| 13.8-inch business, SKU 2036 | Romulus 13 DTB | untested |
| 15-inch consumer, SKU 2037 | Romulus 15 DTB | hardware verification pending |
| 15-inch business, SKU 2037 | Romulus 15 DTB | untested |

Snapdragon X Plus/X Elite, RAM size, and SSD capacity do not select a different
DTB. Form factor and SKU do.

## Functional matrix

| Function | Expected status | Notes |
| --- | --- | --- |
| AArch64 UEFI boot and automatic DTB | CI-tested | Both DTBs are inspected in the UKI/package payload |
| NVMe and installation | untested | Must pass destructive-install checklist on real hardware |
| Keyboard | untested | SPI-HID kernel support is included |
| Touchpad and haptic click | untested | SPI-HID kernel queue, IPTSD fork, and calibration included |
| Touchscreen | known broken | No working upstream SL7 touchscreen stack is available |
| GPU and backlight | untested | Requires extracted Microsoft GPU firmware |
| Wi-Fi | untested | ath12k Romulus enumeration and factory MAC provisioning included |
| Bluetooth | untested | Requires firmware and factory address provisioning |
| Audio | untested | Requires Qualcomm DSP firmware and Fedora ALSA UCM data |
| USB-A / USB-C | untested | Resume reinitialization patch is included |
| External display | untested | Test both USB-C ports and hot plug |
| Battery reporting | untested | Duplicate battery workaround is already in the base kernel |
| Suspend/resume | untested | Test repeated cycles with USB and touchpad |
| Camera | untested | Camera DT/driver changes are included; extracted firmware may be required |

This table must be updated only from a completed report in `hardware-tests/`.
Marketing-style claims based on source availability alone are not accepted.
