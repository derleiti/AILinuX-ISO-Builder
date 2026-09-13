# AILinuX ISO Builder

[![CI](https://github.com/derleiti/AILinuX-ISO-Builder/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/derleiti/AILinuX-ISO-Builder/actions/workflows/ci.yml)
[![Security](https://github.com/derleiti/AILinuX-ISO-Builder/actions/workflows/security.yml/badge.svg?branch=main)](https://github.com/derleiti/AILinuX-ISO-Builder/actions/workflows/security.yml)

Reproducible amd64 live/install ISO builder for **AILinuX 26.04**, based on Ubuntu 26.04 LTS with KDE Plasma, AILinux repositories/packages and Calamares.

## Build

A clean rootless build with validation and available boot smoke tests:

```bash
sudo apt-get update
sudo apt-get install --yes git uidmap util-linux ubuntu-keyring python3
git clone --recurse-submodules https://github.com/derleiti/AILinuX-ISO-Builder.git
cd AILinuX-ISO-Builder
./create.sh
```

The reusable isolated builder lives below `~/.cache/ailinux-distro-builder/`. The host does not need the complete live-build toolchain installed globally.

## Build guarantees

- atomic build lock and preflight checks before destructive cleanup
- rootless user-namespace build path
- checked repository/kernel metadata
- structural ISO verification before publication
- optional/required QEMU BIOS+UEFI boot smoke tests depending on `AILINUX_SMOKE_TESTS`
- offline mode only when required package caches and allow-listed hashes are present
- cleanup/restore traps for temporary offline package staging

Output and SHA-256 files are written to `output/`.

## Direct-host build

```bash
sudo apt-get install --yes live-build debootstrap xorriso squashfs-tools   isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools
./scripts/build.sh
```

## Third-party components

The generated ISO contains Ubuntu, KDE/Plasma, Calamares, Linux and many other components under their own licenses. The Infinity theme/assets also carry their own GPL and upstream notices. AILinux does not relicense those components.

## License

New AILinux-authored builder material is covered by the AILinux Proprietary Source License. Historical versions published under Apache-2.0 retain those rights. See `LICENSE`, `LICENSE-HISTORY.md`, and `NOTICE.md`.
