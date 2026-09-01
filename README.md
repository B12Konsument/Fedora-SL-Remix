# Fedora SL7 Remix

> [!WARNING]
> Fedora SL7 Remix is experimental and is not produced, endorsed, or supported
> by Fedora or Microsoft. Keep Windows and a current backup until the features
> you need have been verified. Secure Boot must be disabled. The touchscreen is
> currently known broken.

Fedora SL7 Remix creates a private Fedora 44 KDE Live ISO for the Snapdragon
Surface Laptop 7. It supports Microsoft system SKU 2036 (13.8-inch) and SKU
2037 (15-inch). Intel/x86_64 models, Surface Pro devices, and other Surface
generations are rejected.

The ISO creator runs on the supported Surface under Windows 11 ARM64. It
detects the model, downloads a verified firmware-free project base, obtains
the device firmware locally, and writes one device-specific ISO to the current
user's Downloads folder. It does not install Linux, repartition a disk, write a
USB drive, use SSH, compile a kernel, require WSL, or require a Fedora VM.

## Supported hardware

| Device | System SKU | DTB | Status |
| --- | --- | --- | --- |
| Surface Laptop 7 13.8-inch | 2036 | Romulus 13 | Supported; physical verification requested |
| Surface Laptop 7 15-inch | 2037 | Romulus 15 | Reference device; verification in progress |

Snapdragon X Plus/X Elite choice, RAM size, and SSD capacity do not change the
DTB. See the evidence-based [hardware status](docs/hardware-status.md) before
installing.

## Create your ISO from Windows

Open PowerShell on the Surface Laptop 7 and run:

```powershell
irm https://raw.githubusercontent.com/B12Konsument/Fedora-SL-Remix/main/windows/install.ps1 | iex
```

This command requires the repository and a compatible prerelease to be
publicly accessible on GitHub. Until the first base release has been published,
the bootstrap stops before downloading an ISO.

The tool requests Administrator access to inspect the signed Windows driver
store and the catalog-signed GPU firmware in System32. It first tries the
firmware already installed by Windows. If required
files are missing, it offers to download the exact Microsoft Surface MSI pinned
in [sources.lock.json](sources.lock.json) and verifies its SHA-256 before
extraction.

The result is named like:

```text
Downloads\Fedora-SL7-Remix-44-0.2.0-Romulus15-PRIVATE.aarch64.iso
```

A SHA-256 file and a redacted JSON provenance report are written beside it.
The ISO contains proprietary Microsoft firmware copied for use on this device.
It is for personal use and must not be redistributed.

For an auditable cloned-repository invocation, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\New-FedoraSl7Iso.ps1
```

Advanced parameters are documented by:

```powershell
Get-Help .\windows\New-FedoraSl7Iso.ps1 -Detailed
```

The stable parameters are `-Release`, `-FirmwareSource`, `-MsiPath`,
`-OutputDirectory`, `-Model`, and `-KeepCache`. Manual `-Model` selection is a
recovery/testing override and displays an additional warning.

## Write and boot the ISO

Use Fedora Media Writer, Rufus in raw/DD mode, or another trusted raw-image
writer. Select the private `Romulus13` or `Romulus15` ISO, not the project base
parts. Writing an image destroys the existing contents of the selected USB
device; verify its model and capacity first.

Disable Secure Boot in Surface UEFI, boot from the USB device, and select the
normal Fedora SL7 Remix entry. The ISO explicitly loads the DTB chosen in
Windows and supplies display firmware before the graphical desktop starts.

The live desktop behaves like a normal Fedora KDE Live environment. Starting
the installer opens interactive Anaconda, where the user selects the target
disk, partitioning, encryption, and installation destination. The project does
not automate those destructive choices. Pay particular attention when an
external SSD and the internal Windows SSD are both connected.

The installed system receives the same firmware and selected SL7 stack through
an explicit Anaconda post-install handoff. The patched `.sl7` kernel remains the
default and a pinned Fedora kernel remains available as a recovery entry.

## Why a Windows personalizer is required

The patched kernel, DTBs, IPTSD, sl7-mac, Anaconda integration, and all other
redistributable components are built once by project CI. The base cannot boot
normally and contains no Microsoft binaries. Its GRUB menu explains that it
must be personalized instead of continuing to a firmware-related black screen.

Windows performs only the private final step:

1. Detect SKU 2036 or 2037.
2. Verify the published base ISO and every split download part.
3. Extract the required device firmware without uploading it.
4. Fill fixed model and firmware areas in a copy of the base ISO.
5. Verify and atomically publish the private result in Downloads.

Windows is not required for the normal Linux driver stack after those files are
installed. Keeping Windows is strongly recommended for Surface firmware
updates, recovery, and continued hardware testing. See
[firmware and Windows](docs/firmware.md).

## Maintainer build

End users do not run this command. Maintainers can build the redistribution-safe
personalization base on Linux:

```bash
git clone https://github.com/B12Konsument/Fedora-SL-Remix.git &&
cd Fedora-SL-Remix &&
sudo ./build.sh
```

The build needs Linux, Podman, privileged loop/mount support, network access,
and at least 20 GiB free. Native AArch64 is the CI-tested host. x86_64 requires
registered AArch64 QEMU user emulation and is much slower.

```text
sudo ./build.sh
sudo ./build.sh --output /path/to/output
sudo ./build.sh --clean
sudo ./build.sh --resume
sudo ./scripts/clean.sh
```

`build.sh` never embeds Microsoft firmware. Output includes the base ISO,
personalization layout, checksums, RPM/source manifests, license report, and
SPDX SBOM. Use `sudo ./scripts/clean.sh` to remove only the known `.build/`,
`out/`, and `.local/state/` generated paths.

See [architecture](docs/architecture.md), [maintainer building](docs/building.md),
and [testing](docs/testing.md) for details.

## Sources and licenses

Every downloaded input is pinned in [sources.lock.json](sources.lock.json).
Primary inputs are Fedora's official
[KIWI descriptions](https://forge.fedoraproject.org/releng/kiwi-descriptions/),
[Fedora kernel dist-git](https://src.fedoraproject.org/rpms/kernel), the
[IPTSD SL7 fork](https://github.com/alex-lentz/iptsd),
[sl7-mac](https://github.com/valeronm/sl7-mac), and the documented
[Surface Laptop 7 Linux research](https://github.com/bryce-hoehn/linux-surface-laptop-7).

Original project scripts, including PowerShell, are GPL-2.0-only. Original
documentation is CC-BY-SA-4.0. Fetched sources retain their upstream licenses.
See [LICENSES.md](LICENSES.md).

## Contributing

Repository content and user-facing text are English only. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before changing pins, the kernel queue, the
personalization format, or hardware status. Never attach firmware, private
ISOs, serial numbers, MAC addresses, or BitLocker information to an issue.
