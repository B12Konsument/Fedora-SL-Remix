# Testing

## Automated checks

Run from the repository root:

```bash
./tests/run.sh
```

Static checks cover source locks, patch metadata, shell syntax, ShellCheck,
KIWI XML, RPM specs, the fixed personalization interface, English-only text,
firmware-manifest validation, release splitting, and Anaconda target copying.

Windows CI runs Pester against SKU mapping, unsupported hardware, fixed-size
selectors, `newc` archive contents, placeholder hashes, overflow rejection,
signature decisions, PnPUtil XML filtering, and firmware completeness. Linux
`cpio` also extracts a PowerShell-generated archive. All test firmware is
synthetic.

Release CI additionally builds the full AArch64 base and verifies EFI boot
files, both DTBs and identifiers, the Romulus QSPI and SPI-HID nodes, the
integrated SPI-HID kernel module, the IPTSD calibration utility, patched and
fallback kernels, contiguous slot extents, the fail-closed GRUB entry, Anaconda
persistence integration, and the absence of Microsoft firmware.

The QEMU test is only a userspace boot smoke test. It cannot validate Surface
UEFI, GPU firmware, input devices, radio, battery, USB resume, camera, or
suspend.

## Physical checklist

On the target Surface, record the release, SKU, CPU, RAM, UEFI version, Windows
firmware source, personalized ISO hash, and kernel. Remove personal identifiers.

1. Run the Windows creator and confirm the detected SKU/model and private output.
2. Write the ISO and reach the graphical KDE live desktop.
3. Confirm the expected Romulus DTB.
4. Install interactively, reboot without USB, and verify firmware persistence.
5. Verify the `.sl7` kernel default and Fedora fallback entry.
6. Test NVMe, keyboard, touchpad, haptics, GPU, brightness, Wi-Fi, Bluetooth,
   audio, battery, USB-A, both USB-C ports, and external displays.
7. Run ten suspend/resume cycles with input, networking, audio, and USB checks.
8. Test camera enumeration and capture.
9. Apply Fedora updates and recheck default/fallback kernels and firmware.

Submit `hardware-tests/template.json` with sanitized logs. The 15-inch release
remains experimental until this checklist passes; the 13.8-inch model requires
accepted community evidence.

### Touchpad diagnostics and calibration

Confirm that the kernel transport created an IPTS touchpad before calibrating:

```bash
sudo iptsd-foreach -t touchpad -- echo '{}'
```

If the command prints a `/dev/hidrawN` device but contacts are missed or
mis-sized, stop its daemon instance and run the packaged calibration utility:

```bash
sudo iptsd-systemd -t touchpad -- stop
sudo iptsd-calibrate /dev/hidrawN
sudo iptsd-systemd -t touchpad -- restart
```

Calibration creates candidate configuration snippets in the current directory.
Review the reported ranges before explicitly copying the recommended snippet to
`/etc/iptsd.d/`; do not replace the packaged calibration automatically.
