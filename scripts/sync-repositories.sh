#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
codename=${AILINUX_TARGET_CODENAME:-resolute}
base_url=${AILINUX_REPO_BASE:-https://repo.ailinux.me/mirror}
manifest="$project_dir/config/mirror-repos.tsv"
archive_key="$project_dir/config/archives/ailinux.key.chroot"
share_key="$project_dir/config/includes.chroot/usr/share/keyrings/ailinux-archive-keyring.gpg"
final_list="$project_dir/config/includes.chroot/etc/apt/sources.list.d/ailinux-mirror.list"
archive_list="$project_dir/config/archives/ailinux-mirrors.list.chroot"
offline=${AILINUX_OFFLINE:-0}
required_ids=${AILINUX_MIRROR_IDS:-ailinux-resolute,kde-neon-resolute,chrome-stable,libreoffice-resolute,ubuntu-resolute,ubuntu-resolute-updates,ubuntu-security-resolute-security}
case "$offline" in 0|1) ;; *) echo "AILINUX_OFFLINE must be 0 or 1." >&2; exit 1 ;; esac
[ "$codename" = resolute ] || { echo "Unsupported ISO target codename: $codename" >&2; exit 1; }
mkdir -p "$(dirname "$share_key")" "$(dirname "$final_list")"
if [ "$offline" = 0 ]; then
    curl -4 -fsSL --retry 3 --connect-timeout 15 "$base_url/mirror-repos.tsv" -o "$manifest.tmp"
    curl -4 -fsSL --retry 3 --connect-timeout 15 "$base_url/ailinux-archive-key.gpg" -o "$archive_key.tmp"
    mv "$manifest.tmp" "$manifest"
    mv "$archive_key.tmp" "$archive_key"
else
    test -s "$manifest" || { echo "Missing cached mirror manifest: $manifest" >&2; exit 1; }
    test -s "$archive_key" || { echo "Missing cached AILinux keyring: $archive_key" >&2; exit 1; }
    echo "Using existing checked repository configuration without network refresh."
fi
install -m 0644 "$archive_key" "$share_key"
python3 "$project_dir/scripts/sync-repositories-v7.py" \
    "$manifest" "$final_list" "$archive_list" "$base_url" "$codename" "$required_ids"
rm -f "$project_dir/config/third-party-repos.json" \
    "$project_dir/config/includes.chroot/etc/apt/sources.list.d/ailinux-mirrors.list" \
    "$project_dir/config/includes.chroot/etc/apt/sources.list.d/third-party.list" \
    "$project_dir/config/includes.chroot/etc/apt/sources.list.d/mozilla.sources"
if [ "$offline" = 0 ]; then
    while IFS='|' read -r repo_id path suite; do
        if [ "$suite" = / ]; then release="$base_url/$path/Release"; else release="$base_url/$path/dists/$suite/Release"; fi
        curl -4 -fsSL --retry 2 --connect-timeout 10 "$release" -o /dev/null || {
            echo "Mirror probe failed: $repo_id ($release)" >&2
            exit 1
        }
    done <<'PROBES'
ailinux-resolute|repo.ailinux.me|resolute
kde-neon-resolute|archive.neon.kde.org/stable|resolute
chrome-stable|dl.google.com/linux/chrome/deb|stable
libreoffice-resolute|ppa.launchpadcontent.net/libreoffice/ppa/ubuntu|resolute
ubuntu-resolute|archive.ubuntu.com/ubuntu|resolute
ubuntu-resolute-updates|archive.ubuntu.com/ubuntu|resolute-updates
ubuntu-security-resolute-security|security.ubuntu.com/ubuntu|resolute-security
PROBES
fi
test -s "$final_list" && test -s "$archive_list"
echo "Repository configuration ready: $final_list"
