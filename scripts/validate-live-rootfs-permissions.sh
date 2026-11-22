#!/bin/sh
# Verify the final SquashFS, not just the build chroot: QEMU previously booted
# with /usr mode 0750 and public asset files 0640, breaking D-Bus and login.
set -eu
image=${1:?Usage: validate-live-rootfs-permissions.sh FILESYSTEM.SQUASHFS}
test -s "$image"
command -v unsquashfs >/dev/null 2>&1 || {
    echo 'Missing unsquashfs for final live-rootfs audit' >&2
    exit 1
}
meta=$(mktemp)
trap 'rm -f "$meta"' EXIT HUP INT TERM
unsquashfs -ll "$image" > "$meta"
awk '
  BEGIN {
    n=split("squashfs-root squashfs-root/usr squashfs-root/usr/lib squashfs-root/usr/lib/systemd squashfs-root/usr/share squashfs-root/usr/share/plasma squashfs-root/usr/share/sddm squashfs-root/usr/share/applications squashfs-root/etc squashfs-root/etc/pam.d squashfs-root/etc/ssh squashfs-root/var/cache/apt squashfs-root/var/cache/apt/archives squashfs-root/var/lib/apt/lists", dirs, " ")
    for (i=1;i<=n;i++) required[dirs[i]]="drwxr-xr-x"
    required["squashfs-root/var/cache/apt/archives/partial"]="drwx------"
    required["squashfs-root/var/lib/apt/lists/partial"]="drwx------"
    required["squashfs-root/usr/bin/dbus-daemon"]="-rwxr-xr-x"
    required["squashfs-root/etc/os-release"]="-rw-r--r--"
    required["squashfs-root/usr/share/applications/ailinux-installer.desktop"]="-rw-r--r--"
  }
  {
    p=$NF
    if (p in required) {
      if ($1!=required[p]) {
        printf "FAIL: %s: expected %s, found %s\n",p,required[p],$1 > "/dev/stderr"
        failed=1
      }
      found[p]=1
    }
  }
  END {
    for (p in required) if (!(p in found)) {
       printf "FAIL: ISO image missing expected path: %s\n",p > "/dev/stderr"
       failed=1
    }
    if (failed) exit 1
    print "PASS: final SquashFS root, KDE, D-Bus and installer file modes verified."
  }
' "$meta"
