# Hardware status

Status terms:

- `CI-tested`: structurally verified or boot-smoked in QEMU only.
- `hardware-verified`: passed the complete checklist on the reference device.
- `community-verified`: passed on hardware reported by another contributor.
- `untested`: implementation exists without accepted physical evidence.
- `known broken`: a known gap prevents normal use.

## Device coverage

| Model | Selector | Status |
| --- | --- | --- |
| Surface Laptop 7 13.8-inch, SKU 2036 | Romulus 13 | untested |
| Surface Laptop 7 15-inch, SKU 2037 | Romulus 15 | hardware verification pending |

Windows creation accepts only Windows 11 ARM64 systems matching those SKU
values. Fedora and Arch creation runs in x86-64 or ARM64 VMs and requires an
explicit physical model selection. Intel Surface models, Surface Pro devices,
and other generations are outside scope. CPU bin, RAM size, and SSD capacity
do not select a different DTB.

## Functional matrix

| Function | Status | Notes |
| --- | --- | --- |
| Windows detection and private ISO creation | CI-tested | Pester uses synthetic fixtures; physical Windows test pending |
| Linux model selection and private ISO creation | CI-tested | Fedora/Arch jobs use synthetic fixtures; physical boot test pending |
| AArch64 UEFI boot and fixed DTB | untested | Base layout and both DTBs are inspected in CI |
| KDE live desktop | untested | Requires early private GPU firmware |
| Anaconda installation and reboot | untested | Private firmware has an explicit post-install handoff |
| NVMe | untested | Physical installation required |
| Keyboard | untested | SPI-HID kernel support included |
| Touchpad and haptics | untested | Patched kernel, IPTSD fork, and calibration included |
| Touchscreen | known broken | No working SL7 stack is available |
| GPU and backlight | untested | Requires `qcdxkmsuc8380.mbn` |
| Wi-Fi and Bluetooth | untested | ath12k and factory-address integration included |
| Audio | untested | Requires personalized Qualcomm DSP firmware |
| Battery | untested | Physical verification pending |
| USB-A / USB-C | untested | Resume reinitialization patch included |
| External displays | untested | Test both USB-C ports and hot plug |
| Suspend/resume | untested | Repeated-cycle testing required |
| Camera | untested | Camera changes included; physical verification pending |

Update this table only from a completed report in `hardware-tests/`. QEMU does
not prove physical compatibility.
