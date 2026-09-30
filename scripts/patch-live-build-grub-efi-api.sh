#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_GRUB_EFI_SCRIPT:-/usr/lib/live/build/lb_binary_grub-efi}
marker=AILINUX_CHECK_PACKAGE_API_COMPAT

if [ ! -f "$target" ]; then
    # Newer Ubuntu live-build no longer ships lb_binary_grub-efi; GRUB2 handles
    # the boot path directly and already uses the current package-helper API.
    grub2=${AILINUX_LIVE_BUILD_GRUB2_SCRIPT:-/usr/lib/live/build/lb_binary_grub2}
    if [ -f "$grub2" ] && \
        grep -Fq 'Check_package chroot/usr/bin/grub-mkimage grub-pc' "$grub2" && \
        ! grep -Eq 'Check_(package|installed)[[:space:]]+chroot[[:space:]]' "$grub2"
    then
        echo "live-build has no separate GRUB EFI helper; current GRUB2 helper API is already compatible."
        exit 0
    fi
    echo "Unsupported live-build installation: $target is missing and no compatible lb_binary_grub2 was found." >&2
    exit 1
fi

if ! grep -Fq "$marker" "$target"; then
    grep -Fq 'Check_package chroot /usr/bin/grub-mkimage grub-common' "$target" || {
        echo "Unsupported lb_binary_grub-efi implementation; refusing to patch." >&2
        exit 1
    }
    sed -i \
      -e 's/Check_package chroot /Check_package /g' \
      -e 's/Check_installed chroot /Check_installed /g' \
      -e 's/Save_package_cache binary/Save_cache cache\/packages.binary/g' \
      "$target"
    sed -i '2i# AILINUX_CHECK_PACKAGE_API_COMPAT: adapt Neon grub-efi caller to current 2-argument package helpers.' "$target"
fi

grep -Fq "$marker" "$target"
! grep -Eq 'Check_(package|installed)[[:space:]]+chroot[[:space:]]' "$target"
! grep -Fq 'Save_package_cache binary' "$target"
echo "Patched live-build GRUB EFI package-helper API compatibility."
