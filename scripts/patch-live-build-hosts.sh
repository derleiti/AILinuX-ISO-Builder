#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_HOSTS_SCRIPT:-/usr/lib/live/build/lb_chroot_hosts}
marker=AILINUX_BUILD_MIRROR_HOST

test "$(id -u)" -eq 0 || {
    echo "The live-build hosts patch must run as root." >&2
    exit 1
}
test -f "$target" || {
    echo "Unsupported live-build installation: $target is missing." >&2
    exit 1
}

if ! grep -Fq "$marker" "$target"; then
    grep -Fq '# Creating stage file' "$target" || {
        echo "Unsupported live-build hosts implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/\t\t# Creating stage file/i\
\t\t# AILINUX_BUILD_MIRROR_HOST: make repo.ailinux.me reachable even if DNS is unavailable in chroot.\
\t\tMIRROR_IP=$(sed -n "1p" .build/ailinux-mirror-ip 2>/dev/null || true)\
\t\tif [ -n "${MIRROR_IP}" ]\
\t\tthen\
\t\t\tprintf "%s\\t%s\\n" "${MIRROR_IP}" repo.ailinux.me >> chroot/etc/hosts\
\t\tfi\
' "$target"
fi

grep -Fq "$marker" "$target"
echo "Patched live-build to pin the AILinux build mirror in the temporary chroot hosts file."
