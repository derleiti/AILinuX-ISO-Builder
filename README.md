# AILinuX 26.04

Reproducible amd64 live/install ISO based on Ubuntu Server 26.04 LTS
(`resolute`) with KDE Plasma, the complete AILinuX mirror configuration,
the AILinuX package suite, and the Calamares installer.

## Build

For a complete clean build from the project root, including validation,
checksum verification and BIOS plus UEFI boot smoke tests:

```bash
./create.sh
```

The script uses the rootless builder and purges live-build's previous chroot,
binary tree and downloaded image-package cache before rebuilding. Only the
isolated Resolute builder environment below `~/.cache/ailinux-distro-builder/`
is reused.

By default, `create.sh` builds from the network: it fetches the AILinuX
repository metadata and pulls the AILinuX packages from `repo.ailinux.me`. A
fresh clone therefore needs nothing but the dependencies below and an internet
connection.

Offline mode is the exception, for a machine that already carries live-build's
package cache and needs to build while `repo.ailinux.me` is unavailable:

```bash
AILINUX_OFFLINE=1 ./create.sh
```

In offline mode the script validates the checked-in
kernel and repository metadata, stages the SHA-256 allow-listed `copa` and
selected `linux-image-*-ailinux` packages from live-build's local cache into
`config/packages.chroot`, and uses the official Ubuntu archive directly. The
temporary packages and disabled AILinuX build archive are restored by a trap on
success, failure or interruption. Offline mode fails on a fresh clone, because
the cached AILinuX packages it stages do not exist there.

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
./scripts/validate-iso-boot.sh output/ailinux-26.04-amd64-latest.iso
AILINUX_QEMU_MODE=bios AILINUX_QEMU_MEDIA=cdrom ./scripts/smoke-test-iso.sh output/ailinux-26.04-amd64-latest.iso
AILINUX_QEMU_MODE=bios AILINUX_QEMU_MEDIA=usb ./scripts/smoke-test-iso.sh output/ailinux-26.04-amd64-latest.iso
AILINUX_QEMU_MODE=uefi AILINUX_QEMU_MEDIA=cdrom ./scripts/smoke-test-iso.sh output/ailinux-26.04-amd64-latest.iso
AILINUX_QEMU_MODE=uefi AILINUX_QEMU_MEDIA=usb ./scripts/smoke-test-iso.sh output/ailinux-26.04-amd64-latest.iso
./scripts/verify-installed-system.sh /mnt/ailinux USERNAME
```

`validate-iso-boot.sh` rejects images without bootable BIOS and UEFI El Torito
entries, hybrid MBR/GPT metadata, the required casper files, or the
device-independent GRUB search used for Ventoy. The smoke tests then boot both
the optical path and the raw hybrid image as USB media. They accept only the
explicit `AILINUX_GRAPHICAL_READY` signal after SDDM is ready. Use
`AILINUX_QEMU_TIMEOUT=180` to change their timeout. These tests do not replace
a final boot on representative physical firmware and a current Ventoy USB
stick. The installed-system audit is read-only and checks the mounted Calamares
target, including its user, Desktop, sudoers policy, kernels, native Firefox,
Oxygen defaults and generated GRUB menu.

## Design

- Ubuntu 26.04 LTS (`resolute`), amd64, hybrid BIOS/UEFI ISO with direct USB
  boot metadata and device-independent casper discovery for Ventoy
- Ubuntu Server base via `ubuntu-server`, with KDE Plasma/Wayland installed as
  explicit desktop packages instead of the Kubuntu desktop meta-package
- Kubuntu libraries and Plymouth branding are purged after package installation;
  the image uses Ubuntu/BGRT Plymouth fallbacks
- Firefox from Mozilla's APT repository (native package, not the Ubuntu Snap
  transition wrapper); its source, key and priority pin are active through
  `config/archives` before live-build resolves packages, and a chroot hook
  aborts the build if the transition package is selected
- Oxygen is the initial Plasma 6 global look-and-feel for the live account and
  every newly installed user; it is seeded through `/etc/skel`, so users can
  change it normally and it is not forced again on later logins
- Calamares graphical installer for physical desktop and server-class PCs
- Calamares' automatic erase layout creates the required UEFI system partition
  on UEFI machines, one ext4 root filesystem and a swap file instead of an
  oversized swap partition; the named cleanup job is loaded as
  `shellprocess@cleanup`
- Calamares users are members of Ubuntu's `sudo` administrator group; the
  installer also writes a mode-0440 sudoers drop-in and checks the complete
  installed policy with `visudo` before installation ends
- Live and installed GRUB show AILinuX plus the concrete kernel version; the
  installed 10-second menu keeps every normal and corresponding `Safe Mode`
  entry at the top level
- Live-only installer and web shortcuts are deleted from the target user's
  Desktop and `/etc/skel` before Calamares finishes
- Casper receives `noprompt`, so reboot still ejects optical live media but no
  longer waits indefinitely for an invisible ENTER keypress in QEMU/KVM
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
