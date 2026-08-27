# Firmware and Windows

## Is Windows required?

Windows is not required for normal Linux operation after the device-specific
firmware has been copied into `/usr/lib/firmware/updates`. Linux loads those
files directly during boot. Wi-Fi/Bluetooth factory addresses are read from a
Surface UEFI variable and also do not require Windows.

Keeping Windows is nevertheless strongly recommended because:

- Microsoft does not grant this project permission to redistribute the
  device-specific Qualcomm firmware.
- A retained Windows installation is a convenient local source for those
  files.
- Surface UEFI, embedded-controller, and other platform firmware updates are
  distributed through Microsoft's Windows update mechanisms. Linux update
  coverage must not be assumed to be equivalent.
- Current community testing reports that a touchpad left in a bad state after
  suspend can sometimes be recovered most reliably by booting Windows once.
  This is a temporary practical dependency, not part of the normal Linux
  driver or firmware-loading path.
- Windows and its recovery environment remain useful while Linux support is
  experimental.

After extraction, Windows may technically be removed, but future platform
updates then require a temporary Windows installation or another supported
Microsoft update method. Deleting Windows is outside this project's installer.

## Supported sources

The preferred order is:

1. An existing, mounted Windows system volume.
2. A local copy of the exact official MSI pinned in `sources.lock.json`.
3. An explicit verified download of that MSI.

Commands:

```bash
sudo sl7-firmware install --windows-root /run/media/user/Windows
sudo sl7-firmware install --msi /path/to/SurfaceLaptop7_ARM_Win11.msi
sudo sl7-firmware install --download
sudo sl7-firmware status
```

The installer mounts plain NTFS volumes read-only. For a BitLocker volume it
uses `dislocker` in read-only mode and may interactively request the owner's
password or recovery material. If automatic unlocking is not possible, unlock
and mount Windows yourself and pass its mount point with `--windows-root`.

## Installed files

The GPU firmware is installed at:

```text
qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn
```

ADSP/CDSP firmware, device trees, and JSON configuration are installed below:

```text
qcom/x1e80100/microsoft/Romulus/
```

The extraction fails if any required filename is absent. It never substitutes
firmware from another Surface generation.

## Redistribution

Microsoft firmware and driver packages remain subject to Microsoft's terms.
The private extraction mode exists for the device owner's personal installation;
it does not provide a redistribution license. Do not upload extracted files,
private ISOs, or private package bundles to GitHub releases or mirrors.
