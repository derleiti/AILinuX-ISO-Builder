#!/bin/sh
# AILinuX ISO repack: rebuild binary tree metadata and produce a bootable ISO
# from the already prepared chroot/ and binary/ trees. Non-destructive: does not
# touch the live-build cache or the chroot itself.
#
# grub-mkrescue needs mtools/mformat, which is absent on the host, so the ISO
# step runs inside the rootless builder root filesystem where mtools exists.
set -eu

project_dir=/home/zombie/AILinuX-Distro
cd "$project_dir"

cache_dir=${AILINUX_BUILDER_CACHE:-"$HOME/.cache/ailinux-distro-builder"}
builder_rootfs="$cache_dir/resolute-rootfs"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== AILinuX repack $stamp ==="

# 1. Promote freshly built squashfs, if a .new exists.
if [ -s binary/casper/filesystem.squashfs.new ]; then
    mv -f binary/casper/filesystem.squashfs.new binary/casper/filesystem.squashfs
    echo "squashfs promoted"
else
    echo "no filesystem.squashfs.new, using existing squashfs"
fi
test -s binary/casper/filesystem.squashfs

# 2. Refresh uncompressed size marker used by casper.
du -sx --block-size=1 chroot 2>/dev/null | cut -f1 > binary/casper/filesystem.size
echo "filesystem.size = $(cat binary/casper/filesystem.size)"

# 3. Re-apply AILinuX GRUB menu titles to the binary tree.
python3 scripts/finalize-binary-grub.py binary/boot/grub/grub.cfg
echo "binary grub.cfg finalized"

# 4. Rebuild checksum manifests inside the binary tree.
(
    cd binary
    rm -f SHA256SUMS md5sum.txt
    find . -type f ! -name SHA256SUMS ! -name md5sum.txt -print0 \
        | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
    find . -type f ! -name SHA256SUMS ! -name md5sum.txt -print0 \
        | LC_ALL=C sort -z | xargs -0 md5sum > md5sum.txt
    sha256sum --check --quiet SHA256SUMS
    md5sum --check --quiet md5sum.txt
)
echo "binary checksums ok"

# 5. Build the hybrid BIOS/UEFI ISO inside the builder root filesystem.
final_iso="output/ailinux-26.04-amd64-${stamp}.iso"
rm -f binary/boot/grub/grub_eltorito
test -x "$builder_rootfs/usr/bin/grub-mkrescue"
test -e "$builder_rootfs/usr/bin/mformat"

unshare --user --map-root-user --map-auto --mount --pid --fork --mount-proc \
    sh -eu -c '
        rootfs=$1
        project=$2
        iso_rel=$3

        mkdir -p "$rootfs/workspace" "$rootfs/dev" "$rootfs/proc" "$rootfs/tmp"
        mount --bind "$project" "$rootfs/workspace"
        mount --rbind /dev "$rootfs/dev"
        mount --make-rslave "$rootfs/dev"
        mount -t proc proc "$rootfs/proc"

        cleanup() {
            umount "$rootfs/proc" 2>/dev/null || true
            umount -R "$rootfs/dev" 2>/dev/null || true
            umount "$rootfs/workspace" 2>/dev/null || true
        }
        trap cleanup EXIT HUP INT TERM

        chroot "$rootfs" /usr/bin/env HOME=/root \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            /bin/sh -eu -c "cd /workspace && grub-mkrescue -o \"\$1\" binary -- -volid AILINUX_2604" sh "$iso_rel"
    ' sh "$builder_rootfs" "$project_dir" "$final_iso"

test -s "$final_iso"

# 6. Checksum and latest-symlink.
(
    cd output
    iso_name=$(basename "$final_iso")
    sha256sum "$iso_name" > "$iso_name.sha256"
    ln -sfn "$iso_name" ailinux-26.04-amd64-latest.iso
    cp "$iso_name.sha256" ailinux-26.04-amd64-latest.iso.sha256
    sha256sum --check "$iso_name.sha256"
)

echo "REPACK_OK $final_iso"
ls -l "$final_iso"
