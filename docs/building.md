# Building and installing

## Recommended installation

1. Disable Secure Boot in Surface UEFI.
2. Back up Windows and the BitLocker recovery key.
3. Boot the official Fedora 44 KDE AArch64 ISO and install Fedora alongside
   Windows. Do not delete the Windows recovery or system volume.
4. Boot Fedora. Use temporary USB input/network devices if necessary.
5. Run:

   ```bash
   git clone https://github.com/B12Konsument/Fedora-SL-Remix.git &&
   cd Fedora-SL-Remix &&
   sudo ./install.sh
   ```

6. Reboot and confirm `uname -r` contains `.sl7.`.
7. Run `sudo sl7-firmware status` and complete any missing firmware with the
   desktop assistant.

The Fedora boot menu retains an unmodified Fedora UKI as a recovery choice.
Routine Fedora updates do not replace the `.sl7` default selected by the
project's systemd service.

For an offline installation, download a release package bundle on another
machine and use `sudo ./install.sh --bundle /path/to/bundle.tar.zst`.

## Optional custom ISO

The build host must be Linux with Podman, at least 80 GiB free space, and an
internet connection. Native AArch64 is supported. An x86_64 host needs working
AArch64 binfmt/QEMU registration and will be substantially slower.

```bash
sudo ./build.sh
```

The default build is safe to redistribute. A private build can embed firmware:

```bash
sudo ./build.sh --with-microsoft-firmware
```

or use a previously downloaded, exactly pinned MSI:

```bash
sudo ./build.sh --firmware-source /path/to/SurfaceLaptop7_ARM_Win11.msi
```

Never publish the private result. The public CI workflow has a separate
denylist inspection, but a local private build intentionally bypasses that
policy.

`--clean` removes only `.build/` inside the repository. `--output` can direct
final artifacts elsewhere; it is never used as a cleanup target.

## Writing the ISO

First identify the entire USB device, not one of its partitions:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

After verifying the target, unmount its partitions and write the image:

```bash
sudo dd if=Fedora-SL7-Remix-44-VERSION.aarch64.iso of=/dev/sdX bs=8M status=progress conv=fsync
```

This overwrites the selected device. Replace `/dev/sdX` only after checking its
model and size. The project cannot recover data written over by `dd`.

## Release downloads

GitHub release assets larger than 2 GiB are published as numbered parts. The
download helper verifies every part, joins them into a temporary file, verifies
the complete ISO, and only then renames it:

```bash
./scripts/download-release.sh latest
```

## Updating pins

Source updates are intentional maintenance work. Update the URL/ref and hash,
run `scripts/fetch-sources.sh`, rebase the minimal patch queue, build the RPMs,
run the automated tests, and attach real-device evidence. Never change a hash
merely to make an unexpected download pass.
