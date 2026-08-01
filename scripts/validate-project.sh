#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

required_files="
create.sh
assets/branding/ailinux-system-logo-source.png
assets/branding/ailinux-system-logo.png
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
config/includes.chroot/etc/calamares/modules/cleanup.conf
config/includes.chroot/etc/calamares/modules/users.conf
config/includes.chroot/etc/calamares/branding/ailinux/stylesheet.qss
config/includes.chroot/etc/apt/preferences.d/firefox-mozilla
config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
config/includes.chroot/etc/systemd/system/casper-md5check.service.d/override.conf
config/includes.chroot/etc/NetworkManager/conf.d/10-globally-managed-devices.conf
config/includes.chroot/etc/NetworkManager/conf.d/20-ailinux-managed-devices.conf
config/includes.chroot/usr/local/bin/ailinux-installer
config/includes.chroot/usr/local/sbin/ailinux-live-autologin
config/includes.chroot/usr/local/sbin/ailinux-installed-cleanup
config/binary_grub/grub.cfg
scripts/prepare-keyrings.sh
scripts/resolve-latest-kernel.sh
scripts/sync-repositories.sh
scripts/finalize-binary-grub.py
config/hooks/0150-remove-kubuntu.chroot
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
    create.sh \
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
    config/hooks/0150-remove-kubuntu.chroot \
    config/hooks/0200-ailinux-initramfs.chroot \
    config/includes.chroot/usr/local/bin/ailinux-installer \
    config/includes.chroot/usr/local/sbin/ailinux-live-autologin \
    config/includes.chroot/usr/local/sbin/ailinux-installed-cleanup
do
    sh -n "$script"
done
python3 -c 'compile(open("scripts/finalize-binary-grub.py", encoding="utf-8").read(), "scripts/finalize-binary-grub.py", "exec")'
python3 scripts/finalize-binary-grub.py --self-test >/dev/null

grep -q 'distribution resolute' auto/config.in
grep -q -- '--bootloader grub2' auto/config.in
grep -q -- '--memtest none' auto/config.in
grep -Fq -- '--linux-packages "linux-image"' auto/config.in
grep -Fq -- '--linux-flavours "$AILINUX_KERNEL_FLAVOUR"' auto/config.in
grep -q 'repo.ailinux.me/mirror/repo.ailinux.me' config/archives/ailinux-mirrors.list.chroot
grep -q '^calamares$' config/package-lists/desktop.list.chroot
grep -q '^ubuntu-server$' config/package-lists/desktop.list.chroot
grep -q '^plasma-desktop$' config/package-lists/desktop.list.chroot
grep -q '^plasma-session-wayland$' config/package-lists/desktop.list.chroot
grep -q '^firefox$' config/package-lists/productivity.list.chroot
if grep -Rqs '^kubuntu-desktop$' config/package-lists; then
    echo "Kubuntu desktop meta-package is forbidden; use Ubuntu Server plus explicit Plasma packages." >&2
    exit 1
fi
for forbidden_kubuntu_package in \
    libkubuntu1 \
    plymouth-theme-kubuntu-logo \
    plymouth-theme-kubuntu-text
do
    grep -Fq "$forbidden_kubuntu_package" config/hooks/0150-remove-kubuntu.chroot
done
grep -Fq '/usr/share/plymouth/themes/bgrt/bgrt.plymouth' \
    config/hooks/0150-remove-kubuntu.chroot
grep -Fq '/usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth' \
    config/hooks/0150-remove-kubuntu.chroot
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
grep -Fxq 'LOGO=ailinux-logo' config/includes.chroot/etc/os-release

# KDE's about-distro KCM resolves LOGO through the hicolor icon theme. Keep
# several native raster sizes so the logo stays sharp in normal and HiDPI UI.
for icon_size in 32 48 64 128 256 512; do
    icon_path="config/includes.chroot/usr/share/icons/hicolor/${icon_size}x${icon_size}/apps/ailinux-logo.png"
    test -s "$icon_path" || {
        echo "Missing AILinuX system logo size: $icon_path" >&2
        exit 1
    }
    python3 -c 'import struct,sys; p=sys.argv[1]; n=int(sys.argv[2]); d=open(p,"rb").read(24); assert d[:8] == b"\x89PNG\r\n\x1a\n"; assert struct.unpack(">II", d[16:24]) == (n,n)' "$icon_path" "$icon_size"
done
test -s config/includes.chroot/usr/share/pixmaps/ailinux-logo.png
grep -Fq 'update-icon-caches /usr/share/icons/hicolor' config/hooks/0100-ailinux-config.chroot
grep -Fq 'update-icon-caches /usr/share/icons/hicolor' config/hooks/live/0100-ailinux-config.hook.chroot

test -f config/includes.chroot/usr/lib/systemd/system/ailinux-live-autologin.service
grep -Fq 'ConditionKernelCommandLine=boot=casper' config/includes.chroot/usr/lib/systemd/system/ailinux-live-autologin.service
test -f config/includes.chroot/etc/systemd/system/getty@tty1.service.d/10-ailinux-live-autologin.conf
test -f config/includes.chroot/etc/systemd/system/serial-getty@ttyS0.service.d/10-ailinux-live-autologin.conf
grep -Fq 'PasswordAuthentication no' config/includes.chroot/etc/ssh/sshd_config.d/90-ailinux-live-security.conf
grep -Fq 'md5sum.txt' scripts/build.sh
grep -Fq 'python3 ./scripts/finalize-binary-grub.py "$project_dir/binary/boot/grub/grub.cfg"' scripts/build.sh
grep -Fq 'AILinuX {version}' scripts/finalize-binary-grub.py
grep -Fq '(Safe Mode)' scripts/finalize-binary-grub.py
if grep -Fq 'ailinux login:' scripts/smoke-test-iso.sh; then
    echo "The ISO smoke test must not accept a text login prompt as graphical success." >&2
    exit 1
fi
grep -Fq 'graphical.target' scripts/smoke-test-iso.sh
grep -Fq 'sddm\.service' scripts/smoke-test-iso.sh


# Installer integrity guards.
grep -Fq 'efiBootLoader: "grub"' config/includes.chroot/etc/calamares/modules/bootloader.conf
grep -Fq 'grubInstall: "grub-install"' config/includes.chroot/etc/calamares/modules/bootloader.conf
grep -Fq 'userSwapChoices: [ file ]' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'initialSwapChoice: file' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'mountPoint: "/"' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'filesystem: "ext4"' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'directory: "efi"' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'size: 100%' config/includes.chroot/etc/calamares/modules/partition.conf
grep -Fq 'mountPoint: /proc' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq 'mountPoint: /sys' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq 'mountPoint: /dev' config/includes.chroot/etc/calamares/modules/mount.conf
grep -Fq '/run/live/medium/md5sum.txt' config/includes.chroot/etc/systemd/system/casper-md5check.service.d/override.conf
grep -Fq 'SidebarBackground:' config/includes.chroot/etc/calamares/branding/ailinux/branding.desc
grep -Fq 'slideshowAPI: 2' config/includes.chroot/etc/calamares/branding/ailinux/branding.desc
grep -Fq 'restartNowMode: user-checked' config/includes.chroot/etc/calamares/modules/finished.conf
grep -Fq 'restartNowCommand: "systemctl -i reboot"' config/includes.chroot/etc/calamares/modules/finished.conf
grep -Fq -- '- cleanup' config/includes.chroot/etc/calamares/settings.conf
grep -Fq 'config:   users.conf' config/includes.chroot/etc/calamares/settings.conf
grep -Fq 'sudoersGroup: sudo' config/includes.chroot/etc/calamares/modules/users.conf
grep -Fq 'sudoersConfigureWithGroup: true' config/includes.chroot/etc/calamares/modules/users.conf
grep -Eq '^[[:space:]]*- sudo$' config/includes.chroot/etc/calamares/modules/users.conf
grep -Fq '${USER}' config/includes.chroot/etc/calamares/modules/cleanup.conf
grep -Fq 'usermod -aG sudo' config/includes.chroot/usr/local/sbin/ailinux-installed-cleanup
grep -Fq 'visudo -cf /etc/sudoers' config/includes.chroot/usr/local/sbin/ailinux-installed-cleanup
grep -Fq 'Pin-Priority: 1001' config/includes.chroot/etc/apt/preferences.d/firefox-mozilla
grep -Fq '#mainApp QLabel' config/includes.chroot/etc/calamares/branding/ailinux/stylesheet.qss
grep -Fq 'color: #7cff00;' config/includes.chroot/etc/calamares/branding/ailinux/stylesheet.qss
grep -Fq 'GRUB_DISTRIBUTOR="AILinuX"' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
grep -Fq 'GRUB_TIMEOUT_STYLE=menu' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
grep -Fq 'GRUB_TIMEOUT=10' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
grep -Fq 'GRUB_DISABLE_SUBMENU=y' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
grep -Fq 'GRUB_DISABLE_RECOVERY=false' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg
grep -Fq 'GRUB_RECOVERY_TITLE="Safe Mode"' config/includes.chroot/etc/default/grub.d/99-ailinux.cfg

# Calamares' partition module contains custom-painted item delegates. Broad
# widget/view rules can make their text unreadable, even when other pages look
# correct. Branding must remain scoped to the application shell.
calamares_qss=config/includes.chroot/etc/calamares/branding/ailinux/stylesheet.qss
if grep -Eq '^[[:space:]]*(QWidget|QLabel|QAbstractItemView|QListView|QTreeView|QTableView)([[:space:],:{]|$)|^[[:space:]]*[A-Za-z#][^{]*::item' "$calamares_qss"; then
    echo "Unsafe broad Calamares selector in $calamares_qss" >&2
    exit 1
fi

for excluded_product in triforce aicoder ai-coder kimi; do
    if grep -Riq --include='*.list.chroot' -- "$excluded_product" config/package-lists; then
        echo "Excluded product found in package lists: $excluded_product" >&2
        exit 1
    fi
done

echo "Project validation passed: Wayland autologin, managed networking, complete repositories, kernel $AILINUX_KERNEL_VERSION."
