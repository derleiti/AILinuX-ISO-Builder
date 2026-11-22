#!/bin/sh
# Reproduce installed-system APT problems in an isolated temp root (no sudo).
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool="$project_dir/config/includes.chroot/usr/local/sbin/ailinux-apt-source-sanity"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/etc/apt/sources.list.d" "$tmp/var/lib/apt/lists/partial" \
         "$tmp/var/cache/apt/archives/partial"
cat > "$tmp/etc/apt/sources.list.d/ailinux-mirror.list" <<'MIRRORS'
deb [arch=amd64,i386 signed-by=/usr/share/keyrings/ailinux-archive-keyring.gpg] https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute main restricted universe multiverse
deb [arch=amd64,i386 signed-by=/usr/share/keyrings/ailinux-archive-keyring.gpg] https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute-updates main restricted universe multiverse
deb [arch=amd64,i386 signed-by=/usr/share/keyrings/ailinux-archive-keyring.gpg] https://repo.ailinux.me/mirror/security.ubuntu.com/ubuntu resolute-security main restricted universe multiverse
MIRRORS
cat > "$tmp/etc/apt/sources.list" <<'BAD'
deb https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute main restricted universe multiverse
deb-src https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute main restricted universe multiverse
deb https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute-updates main restricted universe multiverse
deb-src https://repo.ailinux.me/mirror/archive.ubuntu.com/ubuntu resolute-updates main restricted universe multiverse
deb https://repo.ailinux.me/mirror/security.ubuntu.com/ubuntu resolute-security main restricted universe multiverse
deb-src https://repo.ailinux.me/mirror/security.ubuntu.com/ubuntu resolute-security main restricted universe multiverse
deb https://example.org/custom stable main
BAD
echo 'deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main' \
    > "$tmp/etc/apt/sources.list.d/antigravity.list"
chmod 0750 "$tmp/var/cache/apt" "$tmp/var/cache/apt/archives" "$tmp/var/lib/apt/lists"
chmod 0700 "$tmp/var/cache/apt/archives/partial" "$tmp/var/lib/apt/lists/partial"
"$tool" "$tmp" >/dev/null
[ "$(stat -c %a "$tmp/var/cache/apt")" = 755 ]
[ "$(stat -c %a "$tmp/var/cache/apt/archives")" = 755 ]
[ "$(stat -c %a "$tmp/var/lib/apt/lists")" = 755 ]
[ "$(stat -c %a "$tmp/var/lib/apt/lists/partial")" = 700 ]
[ "$(stat -c %a "$tmp/var/cache/apt/archives/partial")" = 700 ]
[ "$(grep -c '^# Canonical source in ailinux-mirror.list; disabled duplicate:' "$tmp/etc/apt/sources.list")" = 6 ]
grep -Fxq 'deb https://example.org/custom stable main' "$tmp/etc/apt/sources.list"
if grep -qE '^(deb|deb-src) .*repo[.]ailinux[.]me/mirror/(archive|security)[.]ubuntu[.]com' "$tmp/etc/apt/sources.list"; then
  echo 'APT test: a duplicate Ubuntu source remains enabled.' >&2; exit 1
fi
grep -Fxq 'deb [arch=amd64 signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main' \
    "$tmp/etc/apt/sources.list.d/antigravity.list"
cp -a "$tmp/etc/apt/sources.list" "$tmp/apt-first-run"
cp -a "$tmp/etc/apt/sources.list.d/antigravity.list" "$tmp/antigravity-first-run"
"$tool" "$tmp" >/dev/null
cmp -s "$tmp/apt-first-run" "$tmp/etc/apt/sources.list"
cmp -s "$tmp/antigravity-first-run" "$tmp/etc/apt/sources.list.d/antigravity.list"
# Fail closed when canonical sources are absent, rather than disable fallbacks.
sed -i '/resolute-security/d' "$tmp/etc/apt/sources.list.d/ailinux-mirror.list"
if "$tool" "$tmp" >/dev/null 2>&1; then
    echo 'APT test: a partial mirror configuration was unexpectedly accepted.' >&2
    exit 1
fi
echo 'PASS: apt source dedup, _apt traversal, arch filter, idempotency and fail-closed.'
