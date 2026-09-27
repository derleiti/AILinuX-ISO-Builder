#!/bin/sh
set -eu

hosts=${AILINUX_LIVE_BUILD_HOSTS_SCRIPT:-/usr/lib/live/build/lb_chroot_hosts}
resolv=${AILINUX_LIVE_BUILD_RESOLV_SCRIPT:-/usr/lib/live/build/lb_chroot_resolv}
archives=${AILINUX_LIVE_BUILD_ARCHIVES_SCRIPT:-/usr/lib/live/build/lb_chroot_archives}

for f in "$hosts" "$resolv" "$archives"; do
    test -f "$f" || { echo "Unsupported live-build installation: $f is missing." >&2; exit 1; }
done

if ! grep -Fq 'AILINUX_APT_READABLE_HOSTS' "$hosts"; then
    sed -i '/\t\t# Creating stage file/i\
\t\t# AILINUX_APT_READABLE_HOSTS: apt downloads run as _apt.\
\t\tchmod 0644 chroot/etc/hosts\
' "$hosts"
fi

if ! grep -Fq 'AILINUX_APT_READABLE_RESOLV' "$resolv"; then
    sed -i '/\t\t# Creating stage file/i\
\t\t# AILINUX_APT_READABLE_RESOLV: apt downloads run as _apt.\
\t\tif [ -e chroot/etc/resolv.conf ]; then chmod 0644 chroot/etc/resolv.conf; fi\
' "$resolv"
fi

if ! grep -Fq 'AILINUX_APT_READABLE_KEYS' "$archives"; then
    sed -i '/\t\t\t# Rebuild apt indices from scratch\./i\
\t\t\t# AILINUX_APT_READABLE_KEYS: apt downloads run as _apt.\
\t\t\tchmod 0644 chroot/etc/apt/trusted.gpg.d/*.gpg 2>/dev/null || true\
' "$archives"
fi

grep -Fq 'AILINUX_APT_READABLE_HOSTS' "$hosts"
grep -Fq 'AILINUX_APT_READABLE_RESOLV' "$resolv"
grep -Fq 'AILINUX_APT_READABLE_KEYS' "$archives"
echo "Patched live-build files so _apt can read hosts, resolver and trusted keyrings."
