#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
offline=${AILINUX_OFFLINE:-0}
resume_binary=${AILINUX_RESUME_BINARY:-0}
retry_build=${AILINUX_RETRY_BUILD:-0}

case "$offline" in
    0|1) ;;
    *) echo "AILINUX_OFFLINE must be 0 or 1." >&2; exit 1 ;;
esac
case "$resume_binary" in
    0|1) ;;
    *) echo "AILINUX_RESUME_BINARY must be 0 or 1." >&2; exit 1 ;;
esac
case "$retry_build" in
    0|1) ;;
    *) echo "AILINUX_RETRY_BUILD must be 0 or 1." >&2; exit 1 ;;
esac
if [ "$resume_binary" = "1" ] && [ "$retry_build" = "1" ]; then
    echo "AILINUX_RESUME_BINARY and AILINUX_RETRY_BUILD are mutually exclusive." >&2
    exit 1
fi

for tool in lb debootstrap xorriso mksquashfs sha256sum md5sum find sort xargs curl gzip dpkg python3 tee mktemp mformat; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing build dependency: $tool" >&2
        exit 1
    }
done

lock_file="$project_dir/.build.lock"

read_lock_pid() {
    test -s "$lock_file" || return 1
    lock_pid=$(sed -n '1p' "$lock_file")
    case "$lock_pid" in
        ''|0|*[!0-9]*) return 1 ;;
    esac
}

acquire_build_lock() {
    attempts=0
    while [ "$attempts" -lt 2 ]; do
        if (set -C; printf '%s\n' "$$" > "$lock_file") 2>/dev/null; then
            return 0
        fi

        if read_lock_pid && kill -0 "$lock_pid" 2>/dev/null; then
            echo "Build already active with PID $lock_pid: $lock_file" >&2
            exit 1
        fi

        rm -f "$lock_file"
        attempts=$((attempts + 1))
    done

    echo "Unable to acquire build lock: $lock_file" >&2
    exit 1
}

release_build_lock() {
    if read_lock_pid && [ "$lock_pid" = "$$" ]; then
        rm -f "$lock_file"
    fi
}

owns_build_lock=0
pending_iso=
if [ -n "${AILINUX_BUILD_LOCK_PID:-}" ]; then
    read_lock_pid && [ "$lock_pid" = "$AILINUX_BUILD_LOCK_PID" ] || {
        echo "Inherited build lock does not match $lock_file." >&2
        exit 1
    }
else
    acquire_build_lock
    owns_build_lock=1
fi
cleanup_build() {
    status=$?
    trap - EXIT HUP INT TERM
    cleanup_status=0
    if [ -d "$project_dir/.offline-build-state" ]; then
        ./scripts/prepare-offline-build.sh cleanup || cleanup_status=$?
    fi
    if [ -n "$pending_iso" ]; then
        rm -f "$pending_iso" "$pending_iso.sha256"
    fi
    if [ "$owns_build_lock" -eq 1 ]; then
        release_build_lock
    fi
    if [ "$status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
        status=$cleanup_status
    fi
    exit "$status"
}
trap cleanup_build EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

./scripts/resolve-latest-kernel.sh
if [ ! -s config/archives/ailinux.key.chroot ]; then
    ./scripts/prepare-keyrings.sh
fi
./scripts/sync-repositories.sh
./scripts/validate-project.sh
install -m 0755 auto/config.in auto/config

if [ "$offline" = "1" ] && [ "${AILINUX_RESUME_BINARY:-0}" != "1" ]; then
    ./scripts/prepare-offline-build.sh stage
    ./scripts/prepare-offline-build.sh mask-archive
fi

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
    status_file=$(mktemp "${TMPDIR:-/tmp}/ailinux-build-status.XXXXXX")
    if (
        set +e
        run_as_root "$@"
        command_status=$?
        printf '%s\n' "$command_status" > "$status_file"
        exit 0
    ) 2>&1 | tee "$log_file"; then
        tee_status=0
    else
        tee_status=$?
    fi
    test -s "$status_file" || {
        rm -f "$status_file"
        echo "Build command ended without recording its status." >&2
        return 1
    }
    status=$(sed -n '1p' "$status_file")
    rm -f "$status_file"
    if [ "$tee_status" -ne 0 ]; then
        echo "Unable to write the complete build log: $log_file" >&2
        return "$tee_status"
    fi
    return "$status"
}

# Old live-build copies /etc/resolv.conf verbatim. On systemd-resolved hosts
# that is often the 127.0.0.53 stub, which is unreachable from the chroot.
run_as_root ./scripts/patch-live-build-resolv.sh
run_as_root ./scripts/patch-live-build-hosts.sh
run_as_root ./scripts/patch-live-build-permissions.sh
run_as_root ./scripts/patch-live-build-grub-efi-api.sh
run_as_root ./scripts/patch-live-build-iso.sh

prepare_build_mirror_host() {
    mirror_ip=${AILINUX_BUILD_MIRROR_IP:-}
    if [ -z "$mirror_ip" ]; then
        mirror_ip=$(getent ahostsv4 repo.ailinux.me 2>/dev/null | sed -n '1{s/[[:space:]].*//;p;q;}')
    fi
    [ -n "$mirror_ip" ] || {
        echo "Unable to resolve repo.ailinux.me on the build host." >&2
        exit 1
    }
    mkdir -p .build
    printf '%s\n' "$mirror_ip" | run_as_root tee .build/ailinux-mirror-ip >/dev/null
    echo "Pinned build mirror: repo.ailinux.me -> $mirror_ip"
}

if [ "$retry_build" = "1" ]; then
    test -d "$project_dir/cache" || {
        echo "AILINUX_RETRY_BUILD requires an existing live-build package cache." >&2
        exit 1
    }
    # Reusing live-build's stage markers directly is unsafe: bootstrap-cache
    # restore can replace the populated chroot while later chroot or binary
    # stages remain marked as complete. Rebuild both the chroot and binary
    # tree, but retain downloaded packages.
    echo "Retrying with the existing package cache and fresh chroot/binary trees."
    run_as_root lb clean --chroot --binary
    run_as_root ./scripts/repair-bootstrap-devices.sh cache/bootstrap/dev
    # live-build 3.x leaves this marker behind although --chroot removed the
    # restored tree. Force the cached bootstrap to be unpacked again.
    run_as_root rm -f .build/bootstrap_cache.restore
    run_as_root ./auto/config
    prepare_build_mirror_host
    run_logged lb build
elif [ "$resume_binary" = "1" ]; then
    run_logged lb binary
else
    if [ "${AILINUX_PURGE_CACHE:-0}" = "1" ]; then
        run_as_root lb clean --purge
    else
        run_as_root lb clean
    fi
    run_as_root ./auto/config
    prepare_build_mirror_host
    run_logged lb build
fi

if [ ! -s "$project_dir/binary/casper/filesystem.squashfs" ] || [ ! -s "$project_dir/binary/boot/grub/grub.cfg" ]; then
    ./scripts/rebuild-binary-tree.sh
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
    # ISO9660 level 3 permits individual files above 4 GiB. This is required
    # for the full AILinux squashfs and remains a normal ISO9660 image for
    # direct USB boot and Ventoy. Keep native xorriso options after --.
    grub-mkrescue -o "$grub_iso" -iso-level 3 "$project_dir/binary" -- -volid AILINUX_2604
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
pending_iso=$final_iso
install -m 0644 "$iso_path" "$final_iso"
if [ "$iso_path" != "$final_iso" ]; then
    rm -f "$iso_path"
fi
./scripts/validate-iso-boot.sh "$final_iso"
(cd "$project_dir/output" && sha256sum "$(basename "$final_iso")" > "$(basename "$final_iso").sha256")
pending_iso=
# Only touch artifacts created by this build. Historical root-owned test ISOs
# must not turn an otherwise successful rootless build into a failure.
chown "$owner" "$final_iso" "$final_iso.sha256" "$log_file" 2>/dev/null || true
ln -sfn "$(basename "$final_iso")" "$project_dir/output/ailinux-26.04-amd64-latest.iso"
cp -f "$final_iso.sha256" "$project_dir/output/ailinux-26.04-amd64-latest.iso.sha256"
chown -h "$owner" "$project_dir/output/ailinux-26.04-amd64-latest.iso" 2>/dev/null || true
chown "$owner" "$project_dir/output/ailinux-26.04-amd64-latest.iso.sha256" 2>/dev/null || true

echo "ISO: $final_iso"
echo "SHA256: $final_iso.sha256"
