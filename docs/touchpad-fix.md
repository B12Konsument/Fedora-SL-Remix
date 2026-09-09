# Touchpad initialization failure

## Report and scope

The touchpad was reported nonfunctional in both the live ISO and the installed
system on a Surface Laptop 7 15-inch with Snapdragon X Elite (Romulus 15).
The ISO version, running kernel and device logs were not supplied. The source
defects below are confirmed in the repository; their presence on that exact
boot and successful physical remediation still need verification.

## Confirmed source defects

The `romulus-spi-dma-device-tree` entry in `kernel/series.json` used only the
device-tree, SPI-controller and DMA portions of the pinned
[ELLX QSPI patch](https://github.com/ProgrammerIn-wonderland/ELLX-Kernel/commit/cdf898f43cd98bf990ffb059cd0479f94118ac79).
It excluded `drivers/hid/spi-hid/*`, which replaces the earlier generic
ACPI/OF transport with the matching Romulus QSPI transport.

Consequently, the image paired the new `touchpad@0` node with the old
`spi-hid-of` driver. That driver's `spi_hid_of_populate_config()` requires
`input-report-header-address`, `input-report-body-address`,
`output-report-address`, `read-opcode`, `write-opcode` and a reset GPIO.
The new node supplies none of those properties: its driver uses fixed QSPI
protocol addresses and `active`/`reset` pinctrl states. The old probe returns
`-ENODEV` at the first missing property, before creating a HID device for IPTSD.
The diagnostic expected on this path is:

```text
Input report header address not provided.
```

Separately, `image/config-sl7.sh` selected the first matching DTB anywhere
under `/usr/lib/modules`. Both the patched kernel and stock recovery kernel
ship files with the same Romulus names. Directory traversal order could select
the stock DTB, which lacks the downstream touchpad node. Checking only the
model's `compatible` identifier did not detect that mistake.

These defects are shared by the live image and the system installed from it.
Changing IPTSD calibration or restarting its service cannot repair a missing
kernel HID device. The pinned IPTSD package already supplies its udev rule and
`iptsd@.service`; the service is started for detected devices, not enabled as
a single `iptsd.service` at boot.

## Implementation

- Apply the HID driver part of the already checksum-locked QSPI patch together
  with its device tree and DMA implementation. No upstream pin is changed.
- Adapt its external-module Makefile for in-tree Kbuild and declare the SPI,
  OF and pinctrl dependencies. Build the single `CONFIG_SPI_HID=m` transport;
  remove obsolete ACPI/OF/CORE configuration symbols and module expectations.
- Increase the patched kernel build ID to `.sl7.2` so it can replace `.sl7.1`.
- Copy both ISO DTBs only from the image's single patched kernel. Fail the
  image build if that selection is ambiguous.
- Inspect the final ISO for the enabled QSPI touchpad, required reset pinctrl
  states, equality with the boot kernel's DTBs, and presence of `spi-hid.ko`.
  Kernel RPM validation also requires the SPI controller, DMA and uinput modules.

The Linux base build and installed kernel are affected. The personalization
format and Windows/Linux firmware extraction are unchanged.

## Local validation

- `./tests/run.sh` passed in the Fedora AArch64 builder, including ShellCheck
  and the positive/negative DTB fixtures. The Windows CPIO cross-check was
  skipped because PowerShell was unavailable.
- `scripts/build-kernel.sh --prepare-only` applied the complete queue to the
  checksum-verified Fedora 7.1.10 source and packaging revision in the lock.
- The QSPI HID, SPI-GENI and GPI DMA objects and both Romulus DTBs compiled
  successfully with Fedora's AArch64 configuration. BTF debug information and
  Rust were disabled for this targeted compile; this was not a full RPM build.
  The imported HID driver emitted three unused-code warnings.
- Both compiled DTBs passed `scripts/check-touchpad-dtb.py`.

No replacement ISO or kernel RPM set was built in this analysis. Final ISO
inspection, a complete release build and physical validation remain necessary.

### Release-build follow-up

The [first v0.2.7 release run](https://github.com/B12Konsument/Fedora-SL-Remix/actions/runs/34280139730)
passed repository and Windows tests and built the patched kernel RPMs and KIWI
ISO. Final ISO inspection correctly rejected a Romulus DTB without the QSPI
controller. The xorriso log identified the source as the stock
`7.1.10-200.fc44.aarch64` module directory.

Two integration gaps remained: `prepare-personalization-base.sh` repeated the
unrestricted DTB search when rewriting the ISO, and `prepare-kiwi.sh` appended
the SL7 configuration after Fedora's terminal `exit 0`, making it unreachable.
The latter also skipped the SL7 service-enabling and image-branding commands.

KIWI preparation now inserts the integration before the final exit and rejects
an unexpected upstream script layout. ISO personalization uses the staged DTBs
under `/boot/dtb/fedora-sl7-remix`, checks that they match the single patched
kernel, and validates QSPI support before invoking xorriso. Regression tests
execute the generated config and read both DTBs back from a real synthetic ISO;
both tests reproduce failures with the old scripts and pass with the fixes.
The complete release workflow and physical boot must still be rerun.

## Deployment and physical verification

Build a new base with the corrected kernel, then create a new private ISO.
Personalizing an existing published base again does not update its kernel or
DTBs. For an existing installation, install the newly built matching SL7 kernel
RPM set and reboot into `.sl7.2`; restarting IPTSD with `.sl7.1` is insufficient.
An already installed copy of the old ISO is not changed by these repository edits.

Collect these results in both the new live session and the installed system:

```bash
uname -r
tr '\0' '\n' < /sys/firmware/devicetree/base/compatible
sudo journalctl -b -k --no-pager | grep -Ei 'spi.hid|qspi|geni|touchpad|045e|0c77'
sudo iptsd-find-hidraw
systemctl list-units --all 'iptsd@*'
sudo journalctl -b --no-pager -u 'iptsd@*'
grep -A 8 -B 2 -i 'touchpad\|ipts' /proc/bus/input/devices
```

Expect the patched kernel, `microsoft,romulus15`, a bound QSPI HID device,
an IPTSD service instance, and an input device. HID numbering is dynamic;
do not hardcode `/dev/hidraw1`. If HID enumeration works but IPTSD fails,
investigate its journal and SELinux AVCs as a separate userspace issue.

Verify pointer motion, tapping, physical/haptic clicking, two-finger scrolling
and input after ten suspend/resume cycles. Repeat after installation and a cold
boot. The replacement driver's resume behavior remains a hardware-test concern;
the [upstream hardware notes](https://github.com/bryce-hoehn/linux-surface-laptop-7)
also describe trackpad failures after suspend. Complete the existing hardware
report before marking the touchpad verified. This change does not enable the
touchscreen.
