#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_RESOLV_SCRIPT:-/usr/lib/live/build/lb_chroot_resolv}
marker=AILINUX_REAL_RESOLVCONF

test "$(id -u)" -eq 0 || {
    echo "The live-build resolver patch must run as root." >&2
    exit 1
}
test -f "$target" || {
    echo "Unsupported live-build installation: $target is missing." >&2
    exit 1
}

if ! grep -Fq "$marker" "$target"; then
    grep -Fq 'cp /etc/resolv.conf chroot/etc/resolv.conf' "$target" || {
        echo "Unsupported live-build resolver implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/cp \/etc\/resolv.conf chroot\/etc\/resolv.conf/c\
\t\t\t# AILINUX_REAL_RESOLVCONF: systemd-resolved stub (127.0.0.53) is unreachable inside chroot.\
\t\t\tif [ -s /run/systemd/resolve/resolv.conf ]\
\t\t\tthen\
\t\t\t\tcp /run/systemd/resolve/resolv.conf chroot/etc/resolv.conf\
\t\t\telse\
\t\t\t\tcp /etc/resolv.conf chroot/etc/resolv.conf\
\t\t\tfi\
\t\t\tchmod 0644 chroot/etc/resolv.conf' "$target"
fi

grep -Fq "$marker" "$target"
echo "Patched live-build to use a chroot-reachable resolver."
