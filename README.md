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

By default, `create.sh` uses repository-offline mode so an outage of
`repo.ailinux.me` does not block a clean build. It validates the checked-in
kernel and repository metadata, stages the SHA-256 allow-listed `copa` and
selected `linux-image-*-ailinux` packages from live-build's local cache into
`config/packages.chroot`, and uses the official Ubuntu archive directly. The
temporary packages and disabled AILinuX build archive are restored by a trap on
success, failure or interruption. To deliberately refresh AILinuX metadata
from the server, opt in explicitly:

```bash
AILINUX_OFFLINE=0 ./create.sh
```

The default cache locations are `cache/packages.chroot`,
`cache/packages_chroot`, `cache/packages.binary` and `cache/packages_binary`.
Set `AILINUX_OFFLINE_PACKAGE_CACHE` to prepend one additional local cache
directory. A new trusted package version must first be added to
`config/offline-packages.sha256`.

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
- Ubuntu Server base via `ubuntu-server`, with KDE Plasma/Wayland installed as
  explicit desktop packages instead of the Kubuntu desktop meta-package
- Kubuntu libraries and Plymouth branding are purged after package installation;
  the image uses Ubuntu/BGRT Plymouth fallbacks
- Firefox from Mozilla's APT repository (native package, not the Ubuntu Snap
  transition wrapper); its source, key and priority pin are active through
  `config/archives` before live-build resolves packages, and a chroot hook
  aborts the build if the transition package is selected
- Calamares graphical installer for physical desktop and server-class PCs
- Calamares users are members of Ubuntu's `sudo` administrator group; the
  installer also writes a mode-0440 sudoers drop-in and checks the complete
  installed policy with `visudo` before installation ends
- Installed GRUB always shows a 10-second AILinuX menu with each kernel and its
  corresponding recovery (safe-mode) entry at the top level
- A generated AILinuX logo is installed in the hicolor icon theme at six
  raster sizes and selected through `LOGO=ailinux-logo` in KDE System Information
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
