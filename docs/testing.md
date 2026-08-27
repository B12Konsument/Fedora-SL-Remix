# Testing

## Automated checks

Run static validation from the repository root:

```bash
./scripts/validate.sh
```

CI checks source-lock structure, duplicate IDs, hashes, kernel-series metadata,
shell syntax, ShellCheck, XML, RPM spec parsing, and English-only user-facing
text. Full release CI additionally builds every RPM and the ISO, opens the live
root, verifies AArch64 EFI boot, checks both Romulus DTBs, and scans for
prohibited firmware.

Release CI boots the image with AArch64 QEMU and waits for a systemd marker
from the live userspace. Run the same test with
`scripts/qemu-smoke.sh /path/to/image.iso`. QEMU is a boot smoke test only. It
cannot validate an SL7 touchpad, radio, battery controller, suspend path,
camera, DTB selection on Microsoft UEFI, or firmware compatibility.

## Physical-device checklist

Record the exact release/commit, SKU, CPU, RAM, firmware source, UEFI version,
and kernel. Then test:

1. Automatic DTB selection and live boot.
2. Anaconda installation beside Windows and reboot.
3. NVMe stability and fallback-kernel boot entry.
4. Keyboard and touchpad, including physical/haptic click.
5. GPU acceleration, brightness control, and both USB-C display paths.
6. Wi-Fi and Bluetooth addresses across three cold boots.
7. Speakers, microphones, headset, and suspend/resume audio.
8. Battery percentage, charging, and AC transitions.
9. USB-A, both USB-C ports, hot plug, and post-resume operation.
10. Ten suspend/resume cycles with touchpad and networking checks.
11. Camera enumeration and capture.
12. A Fedora update followed by confirmation that the SL7 kernel remains the
    default and the Fedora fallback still boots.

Use `hardware-tests/template.json` and attach relevant journal excerpts. Remove
serial numbers, MAC addresses, BitLocker identifiers, and other personal data.
