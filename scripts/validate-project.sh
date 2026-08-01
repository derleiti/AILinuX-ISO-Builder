#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

required_files="
auto/config.in
config/ailinux-kernel.env
config/package-lists/desktop.list.chroot
config/package-lists/ailinux.list.chroot
config/archives/ailinux-mirrors.list.chroot
config/includes.chroot/etc/calamares/settings.conf
config/includes.chroot/etc/calamares/modules/partition.conf
config/includes.chroot/etc/calamares/modules/bootloader.conf
config/includes.chroot/etc/calamares/modules/mount.conf
config/includes.chroot/etc/calamares/modules/fstab.conf
config/includes.chroot/etc/calamares/modules/welcome.conf
config/includes.chroot/etc/calamares/branding/ailinux/stylesheet.qss
config/includes.chroot/etc/systemd/system/casper-md5check.service.d/override.conf
config/includes.chroot/etc/NetworkManager/conf.d/10-globally-managed-devices.conf
config/includes.chroot/etc/NetworkManager/conf.d/20-ailinux-managed-devices.conf
config/includes.chroot/usr/local/bin/ailinux-installer
config/includes.chroot/usr/local/sbin/ailinux-live-autologin
config/binary_grub/grub.cfg
scripts/prepare-keyrings.sh
scripts/resolve-latest-kernel.sh
scripts/sync-repositories.sh
config/hooks/0200-ailinux-initramfs.chroot
config/third-party-repos.json
config/includes.chroot/etc/apt/sources.list.d/ailinux-mirror.list
scripts/patch-live-build-mounts.sh
scripts/patch-live-build-squashfs.sh
scripts/patch-live-build-iso.sh
"

for path in $required_files; do
    test -e "$path" || {
        echo "Missing: $path" >&2
        exit 1
    }
done

for script in \
    auto/config.in \
    scripts/build.sh \
    scripts/build-rootless.sh \
    scripts/patch-live-build-rootless.sh \
    scripts/patch-live-build-mounts.sh \
    scripts/patch-live-build-squashfs.sh \
    scripts/patch-live-build-iso.sh \
    scripts/prepare-keyrings.sh \
    scripts/resolve-latest-kernel.sh \
    scripts/sync-repositories.sh \
    scripts/smoke-test-iso.sh \
    scripts/validate-project.sh \
    config/hooks/0050-apt-network.chroot_early \
    config/hooks/0100-ailinux-config.chroot \
    config/hooks/live/0100-ailinux-config.hook.chroot \
    config/hooks/0200-ailinux-initramfs.chroot \
    config/includes.chroot/usr/local/bin/ailinux-installer \
    config/includes.chroot/usr/local/sbin/ailinux-live-autologin
do
    sh -n "$script"
done

grep -q 'distribution resolute' auto/config.in
grep -q -- '--bootloader grub2' auto/config.in
grep -q -- '--memtest none' auto/config.in
grep -Fq -- '--linux-packages "linux-image"' auto/config.in
grep -Fq -- '--linux-flavours "$AILINUX_KERNEL_FLAVOUR"' auto/config.in
grep -q 'repo.ailinux.me/mirror/repo.ailinux.me' config/archives/ailinux-mirrors.list.chroot
grep -q '^calamares$' config/package-lists/desktop.list.chroot
grep -q '^copa$' config/package-lists/ailinux.list.chroot
grep -q '^python3$' config/package-lists/productivity.list.chroot
grep -q '^set timeout=5$' config/binary_grub/grub.cfg
grep -q '^serial --unit=0 --speed=115200' config/binary_grub/grub.cfg
grep -q '^terminal_input console serial; terminal_output console serial$' config/binary_grub/grub.cfg

. ./config/ailinux-kernel.env
case "$AILINUX_KERNEL_PACKAGE" in
    linux-image-*-ailinux) ;;
    *) echo "Invalid AILinuX kernel package: $AILINUX_KERNEL_PACKAGE" >&2; exit 1 ;;
esac
test "linux-image-$AILINUX_KERNEL_FLAVOUR" = "$AILINUX_KERNEL_PACKAGE" || {
    echo "Kernel package/flavour mismatch." >&2
    exit 1
}

if grep -RqsE 'plasma-session-x11|startplasma-x11|plasmax11' config/package-lists config/hooks auto; then
    echo "X11 Plasma content is forbidden in the Wayland-only image." >&2
    exit 1
fi

grep -Fq 'add-ailinux-repo.sh' scripts/sync-repositories.sh
grep -Fq 'third-party-repos.json' scripts/sync-repositories.sh
grep -Fq 'update-initramfs.orig.initramfs-tools' config/hooks/0200-ailinux-initramfs.chroot
for stale in \
    config/includes.chroot/etc/apt/sources.list.d/ailinux-mirrors.list \
    config/includes.chroot/etc/apt/sources.list.d/third-party.list \
    config/includes.chroot/etc/apt/sources.list.d/mozilla.sources
do
    test ! -e "$stale" || {
        echo "Stale handwritten repository file remains: $stale" >&2
        exit 1
    }
done

third_party_count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["repos"]))' config/third-party-repos.json)
test "$third_party_count" -ge 11 || {
    echo "Incomplete third-party repository manifest: $third_party_count" >&2
    exit 1
}
test "$(find config/includes.chroot/etc/apt/sources.list.d -maxdepth 1 -type f | wc -l)" -ge 12 || {
    echo "Repository include tree is incomplete." >&2
    exit 1
}

grep -Fq 'DisplayServer=wayland' config/includes.chroot/usr/local/sbin/ailinux-live-autologin
grep -Fq 'Session=$wayland_session' config/includes.chroot/usr/local/sbin/ailinux-live-autologin
grep -Fq 'cat > /etc/sddm.conf' config/includes.chroot/usr/local/sbin/ailinux-live-autologin
grep -Fq 'managed=true' config/includes.chroot/etc/NetworkManager/conf.d/20-ailinux-managed-devices.conf
grep -Fq 'live-media=/dev/disk/by-label/AILINUX_2604 live-media-path=casper' auto/config.in

test -f config/includes.chroot/usr/lib/systemd/system/ailinux-live-autologin.service
grep -Fq 'ConditionKernelCommandLine=boot=casper' config/includes.chroot/usr/lib/systemd/system/ailinux-live-autologin.service
test -f config/includes.chroot/etc/systemd/system/getty@tty1.service.d/10-ailinux-live-autologin.conf
test -f config/includes.chroot/etc/systemd/system/serial-getty@ttyS0.service.d/10-ailinux-live-autologin.conf
grep -Fq 'PasswordAuthentication no' config/includes.chroot/etc/ssh/sshd_config.d/90-ailinux-live-security.conf
grep -Fq 'md5sum.txt' scripts/build.sh


# Installer integrity guards.
grep -Fq 'efiBootLoader: "grub"' config/includes.chroot/etc/calamares/modules/bootloader.conf
grep -Fq 'grubInstall: "grub-install"' config/includes.chroot/etc/calamares/modules/bootloader.conf
grep -Fq 'userSwapChoices: [ file ]' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'initialSwapChoice: file' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'mountPoint: "/"' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'filesystem: "ext4"' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'size: 100%' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'mountPoint: /proc' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq 'mountPoint: /sys' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq 'mountPoint: /dev' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq '/run/live/medium/md5sum.txt' config/includes.chroot/etc/systemd/system/casper-md5check.service.d/override.conf
grep -Fq 'SidebarBackground:' config/includes.chroot/etc/calamares/branding/ailinux/branding.desc
grep -Fq 'slideshowAPI: 2' config/includes.chroot/etc/calamares/branding/ailinux/branding.desc

echo "Project validation passed: Wayland autologin, managed networking, complete repositories, kernel $AILINUX_KERNEL_VERSION."
