#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_BINARY_ROOTFS_SCRIPT:-/usr/lib/live/build/lb_binary_rootfs}
host_original='mksquashfs chroot binary/${INITFS}/filesystem.squashfs ${MKSQUASHFS_OPTIONS}'
host_broken='mksquashfs chroot binary/${INITFS}/filesystem.squashfs ${MKSQUASHFS_OPTIONS} -e dev proc sys run'
host_fixed='mksquashfs chroot binary/${INITFS}/filesystem.squashfs ${MKSQUASHFS_OPTIONS} -one-file-system'
chroot_original='Chroot chroot "mksquashfs chroot filesystem.squashfs ${MKSQUASHFS_OPTIONS}"'
chroot_broken='Chroot chroot "mksquashfs chroot filesystem.squashfs ${MKSQUASHFS_OPTIONS} -e dev proc sys run"'
chroot_fixed='Chroot chroot "mksquashfs chroot filesystem.squashfs ${MKSQUASHFS_OPTIONS} -one-file-system"'

test -f "$target" || {
    echo "Unsupported live-build installation: $target is missing." >&2
    exit 1
}

if grep -Fq "$host_broken" "$target"; then
    sed -i "s@${host_broken}@${host_fixed}@" "$target"
elif ! grep -Fq "$host_fixed" "$target"; then
    grep -Fq "$host_original" "$target" || {
        echo "Unsupported host squashfs implementation; refusing to patch." >&2
        exit 1
    }
    sed -i "s@${host_original}@${host_fixed}@" "$target"
fi

if grep -Fq "$chroot_broken" "$target"; then
    sed -i "s@${chroot_broken}@${chroot_fixed}@" "$target"
elif ! grep -Fq "$chroot_fixed" "$target"; then
    grep -Fq "$chroot_original" "$target" || {
        echo "Unsupported chroot squashfs implementation; refusing to patch." >&2
        exit 1
    }
    sed -i "s@${chroot_original}@${chroot_fixed}@" "$target"
fi

grep -Fq "$host_fixed" "$target"
grep -Fq "$chroot_fixed" "$target"
echo "Patched live-build to preserve empty mountpoints and skip mounted virtual filesystems."
