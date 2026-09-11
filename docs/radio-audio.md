# Radio and speaker failures

## Report and evidence

On 2026-09-11 the user reported a working touchpad in the latest release,
requiring calibration after installation, and nonfunctional Bluetooth, Wi-Fi,
and speakers. The latest published prerelease at investigation time was
v0.2.7. The exact ISO, running kernel, boot logs, and whether the failures occur
in the live session, installed system, or both remain unconfirmed.

This is partial hardware feedback. It does not establish completed hardware
verification for either model or identify every cause of the failures.

## Bluetooth: confirmed packaging defect

The locked [sl7-mac source](https://github.com/valeronm/sl7-mac/blob/b0a562f27e79fc3dd35a0617eba1e96deee000d1/sl7-mac)
defaults to `/usr/lib/sl7-mac/mgmt-set-addr.py`. Our RPM installs that helper
under `/usr/libexec/sl7-mac/`. Consequently, `sl7-mac apply-bt` cannot launch
the helper that configures the controller's factory address. The udev rule
and Bluetooth unit do not override this path.

The RPM now adapts the default to Fedora's libexec path and checks it against
the installed payload during `%check`. ISO inspection checks it again.

On an existing v0.2.7 installation, this explicit override tests the fix
without changing packaged files:

```bash
sudo env SL7_MAC_HELPER=/usr/libexec/sl7-mac/mgmt-set-addr.py sl7-mac apply-bt
sudo systemctl restart bluetooth.service
```

The override lasts for this invocation only; a corrected RPM makes it
persistent. If it fails because the controller or UEFI address is absent,
capture the relevant logs before trying additional workarounds.

## Audio: early firmware availability

The pinned kernel's Romulus device tree enables ADSP and CDSP and requests
`Romulus/qcadsp8380.mbn`, `Romulus/qccdsp8380.mbn`, and their DTB firmware.
Both personalizers previously put only the GPU file in the initramfs firmware
search path. DSP files were stored only in the handoff payload. The pre-pivot
hook copied that payload into `/run`, and a later live service installed it.
That service has no ordering before device coldplug. A remoteproc firmware
request could therefore fail before the DSP files became available; copying
files afterward does not retry the failed probe.

Both personalizers now include all ten files at the early kernel paths, and
the pre-pivot hook also populates the live firmware directory before
switch_root. The manifest, required firmware set, schema, and 256 MiB slot
remain unchanged. Both copies of the locked firmware occupy about 49 MiB
before archive overhead. Rebuild the base and use the updated personalizer
to obtain both changes. Existing private ISOs are not modified automatically.

Anaconda already copies the private firmware into the target and rebuilds
its initramfs. The early-live change alone therefore does not explain or
prove a fix for a persistent speaker failure after installation.

Fedora's locally inspected `qcom-firmware-20260810-1.fc44` provides
`qcom/x1e80100/X1E80100-Romulus-tplg.bin.xz`.
`alsa-ucm-1.2.16.1-1.fc44` matches the Surface Laptop 7 DMI board name and
selects the shared `LENOVO-T14s.conf` profile. The pinned Fedora kernel enables
the X1E80100 sound card, QDSP6, SoundWire codecs, and in-kernel PD mapper.
Those observations do not prove that the affected boot loaded them correctly.
No mixer gain overrides or replacement audio profiles have been added.

## Wi-Fi: board lookup still needs device evidence

The image now explicitly requests Fedora's `atheros-firmware`; ISO inspection
requires the WCN7850 firmware and board database, Bluetooth firmware, and
Romulus audio topology. This avoids relying on transitive package selection.
It does not by itself fix a board-name mismatch.

The locked research notes contain a [board alias workaround](https://github.com/bryce-hoehn/linux-surface-laptop-7/blob/af765428493e13b84f06c23bdea4cedd3e58cf72/fix-board-2-wifi.sh)
for PCI `17cb:1107`, subsystem `17cb:1107`, QMI chip 2, board 255. Fedora's
locally inspected `atheros-firmware-20260810-1.fc44` contains the corresponding
subsystem `17cb:3378` entry but not the `17cb:1107` entry. The pinned ath12k
fallback still uses the subsystem IDs and cannot resolve that missing alias.
The existing RFKill patch addresses a later, separate initialization step.

The affected device's requested board name must be captured before selecting
different board data. No firmware database edits or speculative kernel
fallbacks are applied by this change.

## Device diagnostics

Run on the Surface in each affected boot environment. Before sharing output,
remove MAC/IP addresses, serial numbers, hostnames, and usernames.

```bash
uname -r
sudo sl7-firmware status
rpm -q atheros-firmware qcom-firmware alsa-ucm sl7-mac
rfkill list
sudo journalctl -b -k --no-hostname --no-pager | grep -Ei 'ath12k|bluetooth|qca|remoteproc|q6apm|tplg|firmware.*failed'
sudo journalctl -b -u sl7-bt-mac.service -u sl7-wifi-mac.service --no-hostname --no-pager
cat /proc/asound/cards
aplay -l
wpctl status
```

Record whether the Bluetooth override changes controller availability,
whether ath12k reports missing board data, and whether ALSA exposes the
Romulus card or only a dummy output. Physical validation and a new complete
ISO build remain necessary.

## Local validation

- `tests/run.sh` passed in the Fedora AArch64 builder, including ShellCheck,
  Linux CPIO content checks, the pre-pivot hook, and installation persistence.
- The Windows CPIO cross-check passed separately using PowerShell 7.6.6 and
  native `cpio`; all ten early files matched the persistent payload.
- Pester 5.7.1 on Linux passed 36 of 38 tests. The two catalog-signature tests
  could not run because `Get-AuthenticodeSignature` is Windows-only. Native
  Windows CI remains required.
- `sl7-mac-1.0.0-2.fc44.noarch.rpm` built successfully from the source-lock
  revision with a matching archive hash and passed `%check`. A synthetic
  UEFI fixture and mocked Python launcher exercised the packaged `apply-bt`
  path: the corrected default resolved its helper; the old default failed.
- No complete replacement ISO or physical radio/speaker verification was
  performed. The new final-image checks still need a release build.
