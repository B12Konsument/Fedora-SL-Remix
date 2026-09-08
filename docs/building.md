# Maintainer building and release process

End users should use the Windows or Linux command in the README. This document
covers the redistribution-safe base build; the Linux private personalization
step itself has no Podman, mount, loop-device, or root requirement.

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

The manually dispatched release workflow first checks that the requested tag
matches `VERSION` and does not already exist, then runs repository, Linux, and
native Windows tests. It then builds
the base on AArch64, inspects the mounted live filesystem, runs a QEMU smoke
test, splits the ISO below 1.9 GiB, packages the PowerShell and Bash files, and
finalizes `personalization-layout.json` with part and bundle sizes, hashes,
entrypoint, minimum version, and contained Linux customizer version.

The release verifier expands both bundles and rejects Microsoft firmware,
MSIs, private ISOs, and fixture directories. The workflow uploads the complete
asset set to a draft, publishes it once, and verifies GitHub reports the release
as immutable. Repository release immutability must be enabled before tagging;
it applies only to future releases. Maintainers dispatch the release workflow
with the exact `v<contents-of-VERSION>` tag. The workflow creates that tag only
after validation, image build, QEMU smoke testing, and asset verification, and
refuses any tag name that already exists.

### Publish a release from GitHub Actions

1. Update `VERSION`, the support RPM version and changelog, the Linux
   `SL7_CUSTOMIZER_VERSION`, the hardware-report template, and the versioned
   examples and test fixtures. Run `./tests/run.sh`, commit, and push `main`.
2. Open **Actions > Build experimental AArch64 release > Run workflow**.
   Select branch **main** and enter **v0.2.7** for the current version.
3. Start the workflow and wait for the entire run to succeed. Repository
   checks alone do not build or publish the live ISO.
4. Open **Releases** and confirm the workflow published the new prerelease
   with ISO parts, `personalization-layout.json`, `linux-customizer.tar.gz`,
   `windows-customizer.zip`, `SHA256SUMS`, and the build manifests.
5. Run the normal Windows or Linux command from the README. It selects the
   newest published release, including prereleases. For a 15-inch Surface,
   select Romulus15 when using the Linux creator, write the new private ISO
   to USB, and boot it. `uname -r` should contain `.sl7.2` for this touchpad fix.

Do not create the tag with `git tag` or publish through **Draft a new release**
before running the workflow. That only publishes a source snapshot; it does
not trigger this project's ISO build. The workflow creates the tag and release
after the build and checks succeed. Keep experimental releases as prereleases
until the physical checklist passes.

If a release was already published without its assets, use a new version:
immutable published releases cannot have the missing assets added afterward,
and this workflow refuses to reuse their tags. Version 0.2.7 is prepared to
replace the incomplete v0.2.6 release. Until the complete replacement is
published, the normal bootstrap still selects v0.2.6 and stops because its
personalization layout is missing. Older ISO files do not contain the fix.

## Linux personalization hosts

The end-user Linux personalizer supports Fedora and Arch on x86-64 and ARM64.
It checks these official packages and offers to install missing ones only after
an explicit `[Y/n]` confirmation:

```text
curl jq coreutils findutils cpio msitools tar
```

`msitools` supplies `msiextract`. Fedora installation uses `sudo dnf install`;
Arch uses `sudo pacman -S --needed`. If an architecture's configured official
repositories do not provide a package, the tool stops instead of fetching an
unreviewed binary. All downloads, extraction, hashing, CPIO creation, and ISO
writes subsequently run as the unprivileged user. About 10 GiB must be free on
the output and cache filesystems.

Every GitHub Action is pinned to a commit SHA. Releases remain prereleases
until the 15-inch physical checklist passes. A public job must fail if known
Microsoft firmware paths or an MSI are present.

## Source updates

Update URLs, immutable revisions, SHA-256 values, licenses, purposes, and
upstream status together. Rebase the minimal kernel queue and remove changes
already present in Fedora or upstream. Never replace a checksum merely to make
an unexpected download succeed.
