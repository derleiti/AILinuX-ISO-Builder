#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

owner=$(stat -c '%u:%g' "$project_dir")

for tool in mksquashfs python3 du cp; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing binary-tree rebuild dependency: $tool" >&2
        exit 1
    }
done

test -d chroot || {
    echo "Missing completed chroot: $project_dir/chroot" >&2
    exit 1
}
test -s config/binary_grub/grub.cfg || {
    echo "Missing GRUB template: config/binary_grub/grub.cfg" >&2
    exit 1
}

mkdir -p binary/casper binary/boot/grub binary/.disk

if [ ! -s binary/casper/filesystem.squashfs ]; then
    echo "Rebuilding missing casper filesystem.squashfs from completed chroot..."
    rm -f binary/casper/filesystem.squashfs
    mksquashfs chroot binary/casper/filesystem.squashfs \
        -comp xz -no-progress -one-file-system
fi

du -B 1 -s chroot | cut -f1 > binary/casper/filesystem.size

found_kernel=0
for kernel in chroot/boot/vmlinuz-*; do
    [ -f "$kernel" ] || continue
    version=${kernel##*/vmlinuz-}
    initrd="chroot/boot/initrd.img-$version"
    test -s "$initrd" || {
        echo "Missing initrd for kernel $version: $initrd" >&2
        exit 1
    }
    cp -f "$kernel" "binary/casper/vmlinuz-$version"
    cp -f "$initrd" "binary/casper/initrd.img-$version"
    found_kernel=1
done
[ "$found_kernel" -eq 1 ] || {
    echo "No kernel found under chroot/boot." >&2
    exit 1
}

python3 - <<'PY'
from pathlib import Path
import re

root = Path('.')
template = (root / 'config/binary_grub/grub.cfg').read_text()
common = (root / 'config/common').read_text()
binary = (root / 'config/binary').read_text()

def value(text: str, name: str, default: str = '') -> str:
    m = re.search(rf'^{re.escape(name)}="(.*)"$', text, re.M)
    return m.group(1) if m else default

bootappend = value(binary, 'LB_BOOTAPPEND_LIVE')
if not bootappend:
    bootappend = value(common, 'LB_BOOTAPPEND_LIVE')

entries = []
for kernel in sorted((root / 'binary/casper').glob('vmlinuz-*')):
    version = kernel.name[len('vmlinuz-'):]
    initrd = root / 'binary/casper' / f'initrd.img-{version}'
    if not initrd.is_file():
        raise SystemExit(f'missing initrd for {version}')
    base = f'boot=casper config {bootappend} union=overlay'.strip()
    entries.append(
        f'menuentry "Debian GNU/Linux - live, kernel {version}" {{\n'
        f'\tlinux\t\t/casper/vmlinuz-{version} {base}\n'
        f'\tinitrd\t\t/casper/initrd.img-{version}\n'
        f'}}\n'
    )
    entries.append(
        f'menuentry "Debian GNU/Linux - live, kernel {version} (fail-safe mode)" {{\n'
        f'\tlinux\t\t/casper/vmlinuz-{version} {base} nomodeset\n'
        f'\tinitrd\t\t/casper/initrd.img-{version}\n'
        f'}}\n'
    )

text = template.replace('LINUX_LIVE', '\n'.join(entries))
text = text.replace('LINUX_INSTALL', '').replace('MEMTEST', '')
(root / 'binary/boot/grub/grub.cfg').write_text(text)
PY

if [ ! -s binary/.disk/info ]; then
    printf '%s\n' 'AILinuX 26.04 amd64' > binary/.disk/info
fi

if [ -d config/includes.binary ]; then
    cp -a config/includes.binary/. binary/
fi

chmod 0644 binary/casper/filesystem.squashfs binary/casper/filesystem.size \
    binary/casper/vmlinuz-* binary/casper/initrd.img-* binary/boot/grub/grub.cfg binary/.disk/info

chown -R "$owner" binary

echo "Binary tree ready: squashfs, kernel, initrd and GRUB configuration present."
