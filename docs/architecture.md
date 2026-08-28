# Architecture

Fedora SL7 Remix has one package pipeline and two delivery paths. The primary
path installs the hardware-enablement RPM bundle on top of an official Fedora
44 AArch64 installation. The optional path feeds the same RPM repository into
Fedora's official KDE Live KIWI description and produces a convenience ISO.

```text
pinned Fedora/kernel/community sources
                  |
                  v
       verified source and patch queue
                  |
                  v
   kernel + IPTSD + MAC + support RPMs
                  |
            local RPM metadata repo
             /                \
            v                  v
     install.sh bundle     optional KIWI ISO
```

## Installer-first path

`install.sh` intentionally does not implement a partitioner. Fedora's Anaconda
handles storage, encryption, and dual boot; the project then performs the
SL7-specific bootstrap. This keeps destructive disk logic out of a young
hardware-support project while retaining the useful Asahi-style property: one
command detects the exact machine and installs a coherent, verified platform
stack.

The installer accepts only Fedora 44 on AArch64 and the two consumer Snapdragon
SKU strings for Microsoft models 2036/2037. Intel/x86_64 Surface Laptop 7 for
Business variants are outside the supported hardware scope. Device-tree compatibility strings
provide a fallback when SMBIOS is unavailable. It installs the release RPM
bundle, preserves the Fedora kernel as a fallback, makes the `.sl7` kernel the
default, extracts firmware when an accessible Windows volume is found, rebuilds
all initramfs images, and records detection data in
`/var/lib/fedora-sl7-remix/install.json`.

The installer never writes partition tables and never deletes or modifies the
Windows filesystem. Automatic firmware discovery mounts candidate NTFS volumes
read-only.

## Kernel and hardware selection

The kernel is built from Fedora 44 kernel dist-git. External commits are fetched
by immutable commit URL, checked against SHA-256, applied after Fedora's patch,
and collapsed into Fedora's `linux-kernel-test.patch` hook. The RPM release has
the `.sl7.1` build ID.

The patch generator stops instead of using fuzz when a change no longer applies.
`kernel/series.json` also records changes intentionally omitted because Linux
7.1 already contains their behavior.

Both Romulus device trees are built into `kernel-uki-dtbloader`. Normal boots
use the UKI hardware-ID selector. The optional ISO additionally carries the two
DTBs as regular files for explicit GRUB troubleshooting entries.

The package repository also contains the exact unmodified Fedora UKI, core
modules, and modules RPMs recorded in the source lock. Exact dependencies in
the support package force that installonly kernel to coexist with the patched
`.sl7` kernel, so both installer-first and ISO installations retain a Fedora
recovery boot target. The default-selection service only selects kernels whose
release contains `.sl7.`. RPM transaction file triggers reapply that choice at
the end of kernel installation or removal transactions, and the boot-time
service provides a second consistency check.

## Firmware boundary

Public artifacts contain the extractor, source metadata, and user interface,
but no files extracted from Microsoft packages. Local firmware installation and
private ISO builds verify the exact MSI hash in `sources.lock.json` before
copying only the filenames referenced by the Romulus device tree.

Release inspection opens the live filesystem and rejects public images that
contain any denylisted Microsoft filename.

## Reproducibility

Git commits, generated Git archive hashes, HTTP downloads, individual kernel
patches, the AArch64 Fedora container image, and GitHub Actions are pinned.
Fedora RPM dependencies remain verified by Fedora repository signatures; the
complete project-RPM NEVRA list is emitted beside every image. Outputs also
contain the source lock, license report, checksums, and an SPDX 2.3 SBOM for the
project RPM repository.
