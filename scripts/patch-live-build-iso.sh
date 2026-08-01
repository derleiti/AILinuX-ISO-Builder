#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_BINARY_ISO_SCRIPT:-/usr/lib/live/build/lb_binary_iso}
marker=AILINUX_GRUB2_XORRISO

test -f "$target" || {
    echo "Unsupported live-build installation: $target is missing." >&2
    exit 1
}

if ! grep -Fq "$marker" "$target"; then
    grep -Fq 'Check_stagefile .build/binary_iso' "$target" || {
        echo "Unsupported live-build ISO implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/Check_stagefile \.build\/binary_iso/a\
\
# AILINUX_GRUB2_XORRISO: legacy live-build cannot create a modern GRUB2 hybrid ISO.\
# Keep all binary stages, but let scripts/build.sh call grub-mkrescue afterwards.\
if [ "${LB_BOOTLOADER}" = "grub2" ]\
then\
\tEcho_message "Deferring GRUB2 ISO generation to grub-mkrescue..."\
\tCreate_stagefile .build/binary_iso\
\texit 0\
fi' "$target"
fi

grep -Fq "$marker" "$target"
echo "Patched live-build to defer GRUB2 ISO generation to grub-mkrescue."
