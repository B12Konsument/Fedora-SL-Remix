# Firmware and Windows

## Is Windows required after installation?

No. Linux loads the copied device firmware directly after personalization and
installation. Windows is not part of the normal Linux driver stack.

Keeping Windows is nevertheless strongly recommended while support remains
experimental. It provides the preferred local firmware source, Surface UEFI
and embedded-controller updates, recovery, and a known-good environment for
hardware comparisons.

## Windows ISO creation

The personalizer inventories active Windows driver packages using PnPUtil XML
and accepts their files only when catalog validation and the Microsoft signer
check succeed. It also checks the catalog-signed System32 location used by the
display firmware. It requires:

```text
qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn
qcom/x1e80100/microsoft/Romulus/adsp_dtbs.elf
qcom/x1e80100/microsoft/Romulus/adspr.jsn
qcom/x1e80100/microsoft/Romulus/adsps.jsn
qcom/x1e80100/microsoft/Romulus/adspua.jsn
qcom/x1e80100/microsoft/Romulus/battmgr.jsn
qcom/x1e80100/microsoft/Romulus/cdsp_dtbs.elf
qcom/x1e80100/microsoft/Romulus/cdspr.jsn
qcom/x1e80100/microsoft/Romulus/qcadsp8380.mbn
qcom/x1e80100/microsoft/Romulus/qccdsp8380.mbn
```

If the local set is incomplete, the tool offers the official Microsoft MSI
locked in `sources.lock.json`. It verifies the complete MSI before native
administrative extraction. It never downloads individual firmware from an
unofficial mirror.

The GPU file is supplied during early boot. The remaining files are validated
and applied to the live environment, then explicitly persisted by Anaconda.

## Linux ISO creation

Fedora and Arch hosts obtain firmware only from the complete Microsoft Surface
MSI pinned by each project release. The user may download it through the tool
or provide an existing local copy; both routes require the exact release size
and SHA-256 before extraction. Individual firmware downloads and unofficial
mirrors are never used.

Native Linux tools cannot reproduce Windows DriverStore inventory,
Authenticode, or Microsoft catalog validation. The checksum of the complete
official MSI is therefore the Linux trust boundary. After `msiextract`, every
required firmware basename must have exactly one match. Missing or ambiguous
matches abort creation. The manifest records only the model, SKU, display
size, source type, MSI version, relative firmware paths, and file hashes. It
contains no local path, username, serial number, IP/MAC address, or VM detail.

## Installed-system recovery

The installed `sl7-firmware` command remains available for explicit recovery
or future firmware refreshes:

```bash
sudo sl7-firmware status
sudo sl7-firmware install --msi /path/to/SurfaceLaptop7_ARM_Win11.msi
sudo sl7-firmware install --download
```

Normal installation from a valid personalized ISO does not require rerunning
these commands.

## Legal boundary

Microsoft firmware and driver packages remain subject to Microsoft's terms.
The private workflow does not grant redistribution rights. Never publish the
private ISO, extracted binaries, an MSI, or a firmware archive. Public project
releases and CI artifacts contain placeholders only.
