# Fedora SL7 Remix

> [!WARNING]
> This is an experimental, community-built Fedora Remix. It is not produced,
> endorsed, or supported by Fedora or Microsoft. Keep Windows until firmware
> extraction and every feature you depend on have been verified. Secure Boot
> must be disabled for the first release.

Fedora SL7 Remix builds a Fedora 44 KDE Live ISO for the Snapdragon-based
Microsoft Surface Laptop 7. One image covers the 13.8-inch and 15-inch
consumer Snapdragon models (Microsoft system SKUs 2036 and 2037) by using
Fedora's automatic AArch64 UKI/DTB selection.

The repository contains the complete build automation, package recipes, image
overlay, source lock, tests, and release workflow. Redistributable releases do
not contain Microsoft's proprietary firmware.

Linux does not need Windows for its normal driver stack after the required
device firmware has been extracted. Keeping Windows is still recommended for
Surface UEFI/embedded-controller updates, recovery, and the currently most
reliable reset of a touchpad that occasionally remains broken after suspend.

## Get an ISO

### Build an ISO yourself

To build a redistribution-safe ISO from this repository, run exactly:

```bash
git clone https://github.com/B12Konsument/Fedora-SL-Remix.git &&
cd Fedora-SL-Remix &&
sudo ./build.sh
```

The finished file is written to `out/` and is named
`Fedora-SL7-Remix-44-<version>.aarch64.iso`.
If a build stops before producing an ISO, its complete output is retained in
`out/build.log`.

The build needs Linux, Podman, privileged loop/mount support, an internet
connection, and at least 20 GiB of free space (30 GiB for a private firmware
build). Native AArch64 is the supported
and CI-tested build architecture. x86_64 uses AArch64 emulation and is much
slower. Native Windows, WSL, and Podman Desktop are not supported build hosts.
Windows and macOS users need a Fedora AArch64 VM with privileged loop-device
support; that VM route is not CI-tested yet.

Pass `--with-microsoft-firmware` only for a private ISO that will not be
redistributed.

### Download a published ISO

Download, verify, and join the latest public release:

```bash
git clone https://github.com/B12Konsument/Fedora-SL-Remix.git &&
cd Fedora-SL-Remix &&
./scripts/download-release.sh latest
```

No release ISO has been published yet. Once the first prerelease exists, this
command is the preferred path for most users.

## Install without building an ISO

The installer-first path is optional. Install the official Fedora 44 KDE
AArch64 image while keeping Windows, boot Fedora, then run:

```bash
git clone https://github.com/B12Konsument/Fedora-SL-Remix.git &&
cd Fedora-SL-Remix &&
sudo ./install.sh
```

The installer detects Romulus 13/15, downloads the verified project RPM bundle,
installs the SL7 kernel and services, looks for the retained Windows volume, and
extracts the required firmware. It never partitions a disk or removes Windows.
Use a USB mouse and USB Ethernet adapter during the initial stock Fedora install
if the touchpad or Wi-Fi is not usable yet.

## Supported devices

| Device | SKU | CPU configurations | Status |
| --- | --- | --- | --- |
| Surface Laptop 7 13.8-inch | 2036 | Snapdragon X Plus / X Elite | Supported, community verification needed |
| Surface Laptop 7 15-inch | 2037 | Snapdragon X Elite | Reference device, verification in progress |

Intel Surface Laptop models, including the x86_64 Surface Laptop 7 for
Business variants, Surface Pro 11, the 13-inch first edition, and later Surface
Laptop generations are outside this project's scope.

## Hardware status

The detailed, evidence-based matrix lives in [hardware-status.md](docs/hardware-status.md).
The touchscreen is currently **known broken**. No QEMU result is presented as
proof of physical hardware support.

Automatic DTB selection uses Fedora's `kernel-uki-dtbloader` and contains both
`x1e80100-microsoft-romulus13.dtb` and
`x1e80100-microsoft-romulus15.dtb`. Troubleshooting entries in GRUB can force
either DTB when firmware identification is incorrect. The patched `.sl7`
kernel remains the default, while an exactly pinned, unmodified Fedora UKI is
installed alongside it as a recovery boot target.

## Firmware policy

The public ISO contains only redistributable software and an extraction
assistant. After booting, run:

```bash
sudo sl7-firmware install --msi /path/to/SurfaceLaptop7_ARM_Win11.msi
```

Alternatively, use `sudo sl7-firmware install --download` to fetch the exact
Microsoft MSI recorded in [sources.lock.json](sources.lock.json). The tool
verifies its SHA-256 before extracting files. See [firmware.md](docs/firmware.md)
for the Windows-partition workflow and legal details.

Do not redistribute an ISO produced with `--with-microsoft-firmware`.

## Build interface

```text
sudo ./build.sh
sudo ./build.sh --with-microsoft-firmware
sudo ./build.sh --firmware-source /path/to/SurfaceLaptop7.msi
sudo ./build.sh --output /path/to/output
sudo ./build.sh --clean
```

The output directory contains the ISO, `SHA256SUMS`, an RPM manifest, a source
manifest, a license report, and an SPDX SBOM. Builds stop on changed source
commits, archive hashes, downloaded patch hashes, or firmware hashes.

For implementation details, see [architecture.md](docs/architecture.md). For
building, release verification, and USB writing instructions, see
[building.md](docs/building.md). Before reporting a hardware result, follow
[testing.md](docs/testing.md).

## Sources and attribution

Every pinned input is machine-readable in [sources.lock.json](sources.lock.json).
The primary projects are:

- [Fedora KIWI descriptions](https://forge.fedoraproject.org/releng/kiwi-descriptions/), used as the Fedora 44 KDE Live base.
- [Fedora kernel dist-git](https://src.fedoraproject.org/rpms/kernel), used to build the Fedora kernel RPMs.
- [ELLX-Kernel](https://github.com/ProgrammerIn-wonderland/ELLX-Kernel), source of the currently required SPI-HID, Romulus, and camera changes.
- [Linux support notes for Surface Laptop 7](https://github.com/bryce-hoehn/linux-surface-laptop-7), used as hardware research and test provenance.
- [IPTSD SL7 fork](https://github.com/alex-lentz/iptsd), used for touchpad processing and resume recovery.
- [sl7-mac](https://github.com/valeronm/sl7-mac), used to restore factory Wi-Fi and Bluetooth addresses.
- [qcom-firmware-extract](https://github.com/Radiicall/qcom-firmware-extract), used for extraction from an existing Windows installation.

Project scripts are GPL-2.0-only and project documentation is CC-BY-SA-4.0.
Fetched upstream code retains its own license. See [LICENSES.md](LICENSES.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before updating source locks or kernel
patches. Hardware results are especially useful for the 13.8-inch and
Snapdragon X Plus models. Security issues should follow [SECURITY.md](SECURITY.md).
