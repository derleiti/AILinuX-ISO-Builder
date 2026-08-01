#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache_dir=${AILINUX_BUILDER_CACHE:-"$HOME/.cache/ailinux-distro-builder"}
rootfs="$cache_dir/resolute-rootfs"
debootstrap_root="$cache_dir/debootstrap-package"
bootstrap_marker="$rootfs/.ailinux-builder-ready"
mirror="https://archive.ubuntu.com/ubuntu"
ubuntu_keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg

command -v unshare >/dev/null 2>&1 || {
    echo "unshare is required for the rootless builder." >&2
    exit 1
}
command -v apt-get >/dev/null 2>&1 || {
    echo "apt-get is required to download debootstrap." >&2
    exit 1
}
command -v dpkg-deb >/dev/null 2>&1 || {
    echo "dpkg-deb is required to unpack debootstrap." >&2
    exit 1
}
test -r "$ubuntu_keyring" || {
    echo "Ubuntu archive keyring is required: $ubuntu_keyring" >&2
    exit 1
}

unshare --user --map-root-user --map-auto true
./scripts/resolve-latest-kernel.sh
./scripts/prepare-keyrings.sh
./scripts/sync-repositories.sh
./scripts/validate-project.sh
mkdir -p "$cache_dir"

if [ ! -x "$debootstrap_root/usr/sbin/debootstrap" ]; then
    package_dir="$cache_dir/packages"
    mkdir -p "$package_dir" "$debootstrap_root"
    (
        cd "$package_dir"
        rm -f debootstrap_*.deb
        apt-get download debootstrap
        package=$(find . -maxdepth 1 -type f -name 'debootstrap_*.deb' -print -quit)
        test -n "$package"
        dpkg-deb -x "$package" "$debootstrap_root"
    )
fi

if [ ! -e "$bootstrap_marker" ]; then
    if [ -d "$rootfs" ] && [ -n "$(find "$rootfs" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        failed_rootfs="$cache_dir/resolute-rootfs.failed.$(date -u +%Y%m%dT%H%M%SZ)"
        mv "$rootfs" "$failed_rootfs"
        echo "Moved incomplete build root to: $failed_rootfs"
    fi
    mkdir -p "$rootfs"
    DEBOOTSTRAP_DIR="$debootstrap_root/usr/share/debootstrap" \
        unshare --user --map-root-user --map-auto --mount --pid --fork --mount-proc \
        "$debootstrap_root/usr/sbin/debootstrap" \
        --arch=amd64 \
        --variant=minbase \
        --keyring="$ubuntu_keyring" \
        resolute \
        "$rootfs" \
        "$mirror"
    touch "$bootstrap_marker"
fi

unshare --user --map-root-user --map-auto --mount --pid --fork --mount-proc \
    sh -eu -c '
        rootfs=$1
        project_dir=$2

        mkdir -p "$rootfs/workspace" "$rootfs/dev" "$rootfs/proc" "$rootfs/sys"
        mount --bind "$project_dir" "$rootfs/workspace"
        mount --rbind /dev "$rootfs/dev"
        mount --make-rslave "$rootfs/dev"
        mount -t proc proc "$rootfs/proc"
        mount --rbind /sys "$rootfs/sys"
        mount --make-rslave "$rootfs/sys"
        cp /etc/resolv.conf "$rootfs/etc/resolv.conf"
        install -m 0644 \
            "$project_dir/config/archives/ailinux.key.chroot" \
            "$rootfs/usr/share/keyrings/ailinux-archive-keyring.gpg"
        printf "%s\n" \
            "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu resolute main restricted universe multiverse" \
            "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu resolute-updates main restricted universe multiverse" \
            "deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://security.ubuntu.com/ubuntu resolute-security main restricted universe multiverse" \
            > "$rootfs/etc/apt/sources.list"

        cleanup() {
            umount -R "$rootfs/sys" 2>/dev/null || true
            umount "$rootfs/proc" 2>/dev/null || true
            umount -R "$rootfs/dev" 2>/dev/null || true
            umount "$rootfs/workspace" 2>/dev/null || true
        }
        trap cleanup EXIT HUP INT TERM

        chroot "$rootfs" /usr/bin/env \
            HOME=/root \
            DEBIAN_FRONTEND=noninteractive \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            /bin/sh -eu -c "
                apt-get update
                apt-get install --yes \
                    live-build \
                    python3 \
                    debootstrap \
                    xorriso \
                    squashfs-tools \
                    isolinux \
                    syslinux-common \
                    syslinux-utils \
                    grub-pc-bin \
                    grub-efi-amd64-bin \
                    mtools \
                    dosfstools \
                    ca-certificates \
                    curl \
                    gzip
                cd /workspace
                ./scripts/patch-live-build-rootless.sh
                ./scripts/patch-live-build-mounts.sh
                ./scripts/patch-live-build-squashfs.sh
                ./scripts/patch-live-build-iso.sh
                ./scripts/build.sh
            "
    ' sh "$rootfs" "$project_dir"
