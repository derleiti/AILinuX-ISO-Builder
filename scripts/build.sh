#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

for tool in lb debootstrap xorriso mksquashfs sha256sum md5sum find sort xargs curl gzip dpkg python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing build dependency: $tool" >&2
        exit 1
    }
done

if [ -e .build.lock ]; then
    echo "Build lock exists: $project_dir/.build.lock" >&2
    exit 1
fi

touch .build.lock
trap 'rm -f .build.lock' EXIT HUP INT TERM

./scripts/resolve-latest-kernel.sh
if [ ! -s config/archives/ailinux.key.chroot ]; then
    ./scripts/prepare-keyrings.sh
fi
./scripts/sync-repositories.sh
./scripts/validate-project.sh
install -m 0755 auto/config.in auto/config

mkdir -p output
owner=$(stat -c '%u:%g' "$project_dir")
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="$project_dir/output/build-$timestamp.log"

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

run_logged() {
    if run_as_root "$@" >"$log_file" 2>&1; then
        status=0
    else
        status=$?
    fi
    cat "$log_file"
    return "$status"
}

if [ "${AILINUX_RESUME_BINARY:-0}" = "1" ]; then
    run_logged lb binary
else
    if [ "${AILINUX_PURGE_CACHE:-0}" = "1" ]; then
        run_as_root lb clean --purge
    else
        run_as_root lb clean
    fi
    run_as_root ./auto/config
    run_logged lb build
fi

python3 ./scripts/finalize-binary-grub.py "$project_dir/binary/boot/grub/grub.cfg"

generate_binary_checksums() {
    test -d "$project_dir/binary" || {
        echo "Missing live-build binary tree: $project_dir/binary" >&2
        exit 1
    }
    (
        cd "$project_dir/binary"
        rm -f SHA256SUMS md5sum.txt
        find . -type f ! -name SHA256SUMS ! -name md5sum.txt -print0 |
            LC_ALL=C sort -z |
            xargs -0 sha256sum > SHA256SUMS
        find . -type f ! -name SHA256SUMS ! -name md5sum.txt -print0 |
            LC_ALL=C sort -z |
            xargs -0 md5sum > md5sum.txt
        sha256sum --check --quiet SHA256SUMS
        md5sum --check --quiet md5sum.txt
    )
}

generate_binary_checksums

iso_path=
if grep -q '^LB_BOOTLOADER="grub2"$' config/binary; then
    command -v grub-mkrescue >/dev/null 2>&1 || {
        echo "Missing build dependency: grub-mkrescue" >&2
        exit 1
    }
    test -d "$project_dir/binary" || {
        echo "Missing live-build binary tree: $project_dir/binary" >&2
        exit 1
    }
    grub_iso="$project_dir/ailinux-26.04-amd64-$timestamp.iso"
    rm -f "$project_dir/binary/boot/grub/grub_eltorito" "$grub_iso"
    grub-mkrescue -o "$grub_iso" "$project_dir/binary" -- -volid AILINUX_2604
    iso_path="$grub_iso"
fi

if [ -z "$iso_path" ]; then
    iso_path=$(find "$project_dir" -maxdepth 1 -type f -name 'ailinux-26.04-amd64*.iso' -print -quit)
fi
if [ -z "$iso_path" ]; then
    iso_path=$(find "$project_dir" -maxdepth 1 -type f -name 'live-image-amd64*.iso' -print -quit)
fi
if [ -z "$iso_path" ]; then
    echo "Build finished without an ISO artifact." >&2
    exit 1
fi

final_iso="$project_dir/output/ailinux-26.04-amd64-$timestamp.iso"
install -m 0644 "$iso_path" "$final_iso"
if [ "$iso_path" != "$final_iso" ]; then
    rm -f "$iso_path"
fi
(cd "$project_dir/output" && sha256sum "$(basename "$final_iso")" > "$(basename "$final_iso").sha256")
# Only touch artifacts created by this build. Historical root-owned test ISOs
# must not turn an otherwise successful rootless build into a failure.
chown "$owner" "$final_iso" "$final_iso.sha256" "$log_file" 2>/dev/null || true
ln -sfn "$(basename "$final_iso")" "$project_dir/output/ailinux-26.04-amd64-latest.iso"
cp -f "$final_iso.sha256" "$project_dir/output/ailinux-26.04-amd64-latest.iso.sha256"
chown -h "$owner" "$project_dir/output/ailinux-26.04-amd64-latest.iso" 2>/dev/null || true
chown "$owner" "$project_dir/output/ailinux-26.04-amd64-latest.iso.sha256" 2>/dev/null || true

echo "ISO: $final_iso"
echo "SHA256: $final_iso.sha256"
