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
releases contain placeholders only.
