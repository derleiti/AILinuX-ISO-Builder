#!/bin/sh
# Verify umask 0027 / checkout-mode regressions without touching live systems.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/scripts" "$tmp/config/includes.chroot/usr/share" "$tmp/config/includes.chroot/usr/lib" "$tmp/config/includes.chroot/etc" "$tmp/config/includes.chroot/usr/share/plasma" "$tmp/config/includes.chroot/usr/share/sddm"
cp "$project_dir/scripts/normalize-iso-include-perms.sh" "$tmp/scripts/"
find "$tmp/config/includes.chroot" -type d -exec chmod 0750 {} +
printf 'public\n' > "$tmp/config/includes.chroot/etc/os-release"
printf '#!/bin/sh\nexit 0\n' > "$tmp/config/includes.chroot/usr/lib/test-script"
printf 'secret\n' > "$tmp/config/includes.chroot/etc/private-token"
chmod 0640 "$tmp/config/includes.chroot/etc/os-release"
chmod 0750 "$tmp/config/includes.chroot/usr/lib/test-script"
chmod 0600 "$tmp/config/includes.chroot/etc/private-token"
sh "$tmp/scripts/normalize-iso-include-perms.sh" >/dev/null
[ "$(stat -c %a "$tmp/config/includes.chroot/usr/lib")" = 755 ]
[ "$(stat -c %a "$tmp/config/includes.chroot/etc/os-release")" = 644 ]
[ "$(stat -c %a "$tmp/config/includes.chroot/usr/lib/test-script")" = 755 ]
[ "$(stat -c %a "$tmp/config/includes.chroot/etc/private-token")" = 600 ]
sh "$tmp/scripts/normalize-iso-include-perms.sh" >/dev/null
[ "$(stat -c %a "$tmp/config/includes.chroot/etc/private-token")" = 600 ]
echo 'PASS: ISO include permissions normalized, private-mode files preserved, idempotent.'
