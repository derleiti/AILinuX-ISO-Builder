#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive_dir="$project_dir/config/archives"
share_keyring_dir="$project_dir/config/includes.chroot/usr/share/keyrings"

mkdir -p "$archive_dir" "$share_keyring_dir"

system_keyring=/usr/share/keyrings/ailinux-archive-keyring.gpg
pinned_keyring="$archive_dir/ailinux.key.chroot"
if [ -r "$system_keyring" ]; then
    source_path=$system_keyring
elif [ -s "$pinned_keyring" ]; then
    source_path=$pinned_keyring
    echo "Using the repository-pinned AILinuX keyring bootstrap: $pinned_keyring"
else
    echo "Required AILinuX keyring is missing: $system_keyring" >&2
    exit 1
fi

if [ "$source_path" != "$pinned_keyring" ]; then
    install -m 0644 "$source_path" "$pinned_keyring"
fi
install -m 0644 "$source_path" "$share_keyring_dir/ailinux-archive-keyring.gpg"

echo "AILinuX build keyring prepared. Third-party keys are installed from the public repository manifest."
