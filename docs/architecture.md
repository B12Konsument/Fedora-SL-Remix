# Architecture

Fedora SL7 Remix separates redistributable compilation from private device
personalization:

```text
pinned Fedora and community sources
                |
                v
  SL7 kernel, RPMs, KDE Live, Anaconda
                |
                v
 firmware-free base ISO + checksum-locked release metadata
                |
                v
 Windows SKU detection + local firmware extraction
                |
                v
 private Romulus13 or Romulus15 Live ISO
```

## Base image

Linux CI builds Fedora 44's `KDE-Desktop-Live` KIWI profile with the local RPM
repository. It then adds both Romulus DTBs, a 4 KiB model-selector file, and a
256 MiB uncompressed `newc` CPIO placeholder as contiguous ISO extents.
`personalization-layout.json` records the exact offsets, lengths, placeholder
hashes, base hash, source-lock hash, supported SKU map, and release parts.

The base contains no Microsoft firmware and is not end-user boot media. Its
placeholder selector exposes only a GRUB explanation. A personalized selector
loads the selected DTB and appends the CPIO slot to Fedora's normal initrd.

Changing a reserved extent invalidates Fedora's embedded whole-volume MD5. The
base therefore clears that field and does not offer `rd.live.check`. SHA-256 is
used for release parts, the complete base, and the private output.

## Windows boundary

The PowerShell 5.1 personalizer runs without WSL or downloaded executables. It
accepts only Windows 11 ARM64 and SKU 2036/2037. On those supported devices, a
warned manual override can force the alternate DTB for recovery testing. It
verifies every release component before opening the ISO for fixed-offset
writes.

The firmware archive contains the GPU firmware at its early kernel path and a
complete validated tree under `/sl7-personalization`. It contains a redacted
manifest with model, SKU, source type, and file hashes; it never records serial
numbers, network addresses, usernames, or local paths.

## Live and installed firmware

The additional initrd makes display firmware available during early boot. A
dracut pre-pivot hook copies the private tree to the live root's `/run`.
`sl7-personalize-live.service` validates every hash and installs the complete
tree into the live overlay before networking and the display manager.

Anaconda does not install that overlay. The support RPM therefore supplies an
internal Anaconda post script, which validates and copies the same tree into
the target, restores labels, regenerates initramfs images, and reapplies the
SL7-kernel default policy. Installation fails instead of producing an
unbootable target when personalization is missing or corrupt.

## Kernel policy

The patched Fedora kernel uses the `.sl7.1` build ID. The support RPM also has
exact dependencies on the pinned unmodified Fedora modules and
`kernel-uki-dtbloader` RPM. Transaction triggers and a boot service keep the
SL7 kernel selected while retaining Fedora's kernel as a recovery target.

## Release boundary

Public releases contain only the firmware-free base split below GitHub's asset
limit, layout JSON, Windows customizer bundle, source/RPM/license manifests,
checksums, and an SBOM. CI scans the live root and ISO for Microsoft firmware.
Private personalized images never enter CI or GitHub releases.
