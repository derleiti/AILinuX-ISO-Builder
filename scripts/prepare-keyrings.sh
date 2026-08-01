#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive_dir="$project_dir/config/archives"
share_keyring_dir="$project_dir/config/includes.chroot/usr/share/keyrings"

mkdir -p "$archive_dir" "$share_keyring_dir"

source_path=/usr/share/keyrings/ailinux-archive-keyring.gpg
if [ ! -r "$source_path" ]; then
    echo "Required AILinuX keyring is missing: $source_path" >&2
    exit 1
fi

install -m 0644 "$source_path" "$archive_dir/ailinux.key.chroot"
install -m 0644 "$source_path" "$share_keyring_dir/ailinux-archive-keyring.gpg"

echo "AILinuX build keyring prepared. Third-party keys are installed from the public repository manifest."
