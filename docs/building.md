# Maintainer building and release process

End users should use the Windows command in the README. This document covers
the redistribution-safe base build.

## Requirements

- Linux with Podman.
- Native AArch64, or x86_64 with registered AArch64 binfmt/QEMU emulation.
- Privileged loop devices and mounts.
- Network access and at least 20 GiB free.

Run:

```bash
sudo ./build.sh
```

Artifacts are written to `out/`. The ISO is named
`Fedora-SL7-Remix-44-<version>-base.aarch64.iso`. It deliberately contains no
Microsoft firmware and refuses normal boot until personalized.

Options:

```text
sudo ./build.sh --output /path/to/output
sudo ./build.sh --clean
sudo ./build.sh --resume
```

`--clean` removes the build cache before rebuilding. `--resume` reuses an
already validated local RPM repository after a KIWI-stage failure. Do not
resume after changing packages, image configuration, source locks, or kernel
patches.

To remove all known generated repository artifacts, including root-owned KIWI
trees and old output images, run:

```bash
sudo ./scripts/clean.sh
```

Add `--include-container` only when the exact local builder image should also
be removed.

## Release preparation

Tag CI builds the base on AArch64, inspects the mounted live filesystem, runs a
QEMU smoke test, splits the ISO below 1.9 GiB, packages the PowerShell files,
and finalizes `personalization-layout.json` with part and bundle hashes.

Every GitHub Action is pinned to a commit SHA. Releases remain prereleases
until the 15-inch physical checklist passes. A public job must fail if known
Microsoft firmware paths or an MSI are present.

## Source updates

Update URLs, immutable revisions, SHA-256 values, licenses, purposes, and
upstream status together. Rebase the minimal kernel queue and remove changes
already present in Fedora or upstream. Never replace a checksum merely to make
an unexpected download succeed.
