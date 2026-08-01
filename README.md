# AILinuX 26.04

Reproducible amd64 live/install ISO based on Ubuntu Server 26.04 LTS
(`resolute`) with KDE Plasma, the complete AILinuX mirror configuration,
the AILinuX package suite, and the Calamares installer.

## Build

For a complete clean build from the project root, including validation,
checksum verification and a BIOS boot smoke test:

```bash
./create.sh
```

The script uses the rootless builder and purges live-build's previous chroot,
binary tree and downloaded image-package cache before rebuilding. Only the
isolated Resolute builder environment below `~/.cache/ailinux-distro-builder/`
is reused.

For a direct host build with preinstalled dependencies:

```bash
sudo apt-get update
sudo apt-get install --yes live-build debootstrap xorriso squashfs-tools \
  isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools
./scripts/build.sh
```

The finished ISO and its SHA-256 checksum are written to `output/`.

If host sudo is unavailable, use the isolated user-namespace builder:

```bash
./scripts/build-rootless.sh
```

It creates a reusable Resolute build root below
`~/.cache/ailinux-distro-builder/` and does not install packages on the host.

## Validation

```bash
./scripts/validate-project.sh
./scripts/smoke-test-iso.sh
```

The smoke test boots the ISO with QEMU in BIOS mode, without touching a disk.
Use `AILINUX_QEMU_TIMEOUT=180` to change its timeout.

## Design

- Ubuntu 26.04 LTS (`resolute`), amd64, hybrid BIOS/UEFI ISO
- KDE Plasma via `kubuntu-desktop`
- Calamares graphical installer for physical desktop and server-class PCs
- Official Ubuntu bootstrap with signed AILinuX mirrors for all image packages
- All current AILinuX packages from `repo.ailinux.me`
- Active third-party repositories from the reference AILinuX workstation
- NetworkManager, SDDM, PipeWire, printing, Bluetooth and common filesystem tools

The build imports repository keyrings from the trusted reference host at build
time. It deliberately does not store private credentials, API keys or user
configuration in the ISO.

`ailinux-libxml2-compat` is rebuilt locally from its verified package metadata
because the current AILinuX repository index lists it while the tiny
metadata-only `.deb` is absent from the pool.
=======
# AILinuX-ISO-Builder
Bulds an actual AILinuX ISO
