#!/bin/sh
# Git does not track directory modes. A checkout with umask 0027 gives all
# include directories 0750 and all normally readable files 0640. live-build
# copies those modes to /usr, /etc and KDE resources, breaking dbus, PAM and
# unprivileged desktop access. Normalize ONLY this public image-include tree.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
includes="$project_dir/config/includes.chroot"
[ -d "$includes" ] || { echo 'Missing ISO include directory' >&2; exit 1; }
find "$includes" -type d -perm 0750 -exec chmod 0755 {} +
find "$includes" -type f -perm 0640 -exec chmod 0644 {} +
find "$includes" -type f -perm 0750 -exec chmod 0755 {} +
# Never broaden access to intentionally protected modes such as 0700 / 0600.
for path in "$includes" "$includes/usr" "$includes/usr/lib" \
            "$includes/usr/share" "$includes/usr/share/sddm" \
            "$includes/usr/share/plasma" "$includes/etc"; do
    [ "$(stat -c %a "$path")" = 755 ] || {
        echo "ISO includes cannot be traversed by desktop users: $path" >&2
        exit 1
    }
done
printf '%s\n' 'Normalized ISO include directory and public-file permissions.'
