#!/bin/sh
set -eu

LC_ALL=C
export LC_ALL

if [ "$#" -ne 2 ]; then
    echo "Usage: $(basename "$0") OUTPUT_ISO BINARY_DIR" >&2
    exit 2
fi

output_iso=$1
binary_dir=$2

command -v grub-mkrescue >/dev/null 2>&1 || {
    echo "Missing build dependency: grub-mkrescue" >&2
    exit 1
}

case "$output_iso" in
    /*) ;;
    *) output_iso=$PWD/$output_iso ;;
esac

binary_dir=$(CDPATH= cd -- "$binary_dir" && pwd)
test -d "$binary_dir/casper" || {
    echo "Missing casper directory: $binary_dir/casper" >&2
    exit 1
}

# grub-mkrescue passes unknown options to xorriso's mkisofs emulation.
# Do not insert `--`: for grub-mkrescue it switches xorriso into native command
# mode, where --sort-weight is invalid and the boot files remain at the ISO end.
set -- grub-mkrescue -o "$output_iso" -volid AILINUX_2604

kernel_count=0
for file in "$binary_dir"/casper/vmlinuz-*; do
    [ -f "$file" ] || continue
    iso_path=${file#"$binary_dir"}
    set -- "$@" --sort-weight 10000 "$iso_path"
    kernel_count=$((kernel_count + 1))
done

initrd_count=0
for file in "$binary_dir"/casper/initrd.img-*; do
    [ -f "$file" ] || continue
    iso_path=${file#"$binary_dir"}
    set -- "$@" --sort-weight 9900 "$iso_path"
    initrd_count=$((initrd_count + 1))
done

[ "$kernel_count" -gt 0 ] || {
    echo "No versioned kernel found below $binary_dir/casper" >&2
    exit 1
}
[ "$initrd_count" -gt 0 ] || {
    echo "No versioned initrd found below $binary_dir/casper" >&2
    exit 1
}

test -s "$binary_dir/casper/filesystem.squashfs" || {
    echo "Missing filesystem.squashfs below $binary_dir/casper" >&2
    exit 1
}

# Keep the files needed before Linux starts in the first ISO area. Without an
# explicit order, grub-mkrescue/xorriso sorts filesystem.squashfs before initrd
# and vmlinuz, which can put both near the 4 GiB edge and break UEFI optical boot.
set -- "$@" \
    --sort-weight 9800 /efi.img \
    --sort-weight 9700 /boot/grub/grub.cfg \
    --sort-weight -10000 /casper/filesystem.squashfs

# Source trees belong after the mkisofs options. This also makes the generated
# command easy to inspect and prevents a source path from ending option parsing.
set -- "$@" "$binary_dir"

printf 'Building hybrid ISO with early kernel/initrd placement: %s\n' "$output_iso"
exec "$@"
