#!/bin/sh
set -eu

if [ "${AILINUX_CREATE_SNAPSHOT_ACTIVE:-0}" != "1" ]; then
    project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    snapshot_path=$(mktemp "${TMPDIR:-/tmp}/ailinux-create.XXXXXX")

    cleanup_bootstrap_snapshot() {
        status=$?
        trap - EXIT HUP INT TERM
        rm -f "$snapshot_path"
        exit "$status"
    }
    trap cleanup_bootstrap_snapshot EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    cp "$0" "$snapshot_path"
    chmod 0600 "$snapshot_path"
    exec env \
        AILINUX_CREATE_SNAPSHOT_ACTIVE=1 \
        AILINUX_CREATE_PROJECT_DIR="$project_dir" \
        AILINUX_CREATE_SNAPSHOT_PATH="$snapshot_path" \
        /bin/sh "$snapshot_path" "$@"
fi

project_dir=${AILINUX_CREATE_PROJECT_DIR:?Missing AILINUX_CREATE_PROJECT_DIR}
snapshot_path=${AILINUX_CREATE_SNAPSHOT_PATH:-}
cd "$project_dir"

cleanup_snapshot_only() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$snapshot_path" ]; then
        rm -f "$snapshot_path"
    fi
    exit "$status"
}
trap cleanup_snapshot_only EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run create.sh with sudo or as root." >&2
    echo "The rootless builder requests privilege only for isolated setup steps." >&2
    echo "Run: bash create.sh" >&2
    exit 1
fi

AILINUX_OFFLINE=${AILINUX_OFFLINE:-0}
AILINUX_RESET_ONLY=${AILINUX_RESET_ONLY:-0}
AILINUX_PURGE_CACHE=${AILINUX_PURGE_CACHE:-auto}
case "$AILINUX_OFFLINE:$AILINUX_RESET_ONLY" in
    0:0|0:1|1:0|1:1) ;;
    *)
        echo "AILINUX_OFFLINE and AILINUX_RESET_ONLY must be 0 or 1." >&2
        exit 1
        ;;
esac
case "$AILINUX_PURGE_CACHE" in
    auto)
        if [ "$AILINUX_OFFLINE" = "1" ]; then
            AILINUX_PURGE_CACHE=0
        else
            AILINUX_PURGE_CACHE=1
        fi
        ;;
    0|1) ;;
    *)
        echo "AILINUX_PURGE_CACHE must be auto, 0 or 1." >&2
        exit 1
        ;;
esac
if [ "$AILINUX_OFFLINE:$AILINUX_PURGE_CACHE" = "1:1" ]; then
    echo "AILINUX_PURGE_CACHE=1 cannot be combined with offline mode." >&2
    echo "Offline builds require the retained live-build package cache." >&2
    exit 1
fi
export AILINUX_OFFLINE AILINUX_PURGE_CACHE

create_lock="$project_dir/.create.lock"
build_lock="$project_dir/.build.lock"
apparmor_key=kernel.apparmor_restrict_unprivileged_userns
apparmor_original=
latest_iso="$project_dir/output/ailinux-26.04-amd64-latest.iso"
known_good_iso="$project_dir/output/ailinux-26.04-amd64-known-good.iso"
previous_latest_target=
build_attempted=0
build_verified=0

mkdir -p "$project_dir/output"
if [ -L "$latest_iso" ]; then
    candidate=$(readlink "$latest_iso" 2>/dev/null || true)
    case "$candidate" in
        ''|*/*)
            ;;
        *)
            if [ -s "$project_dir/output/$candidate" ]; then
                previous_latest_target=$candidate
            fi
            ;;
    esac
fi

lock_is_active() {
    lock_file=$1
    test -s "$lock_file" || return 1
    lock_pid=$(cat "$lock_file" 2>/dev/null || true)
    case "$lock_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$lock_pid" 2>/dev/null
}

if [ -e "$create_lock" ]; then
    if lock_is_active "$create_lock"; then
        echo "Another create.sh process is active (PID $(cat "$create_lock"))." >&2
        exit 1
    fi
    rm -f "$create_lock"
fi

if [ -e "$build_lock" ]; then
    if lock_is_active "$build_lock"; then
        echo "A build is already active (PID $(cat "$build_lock"))." >&2
        exit 1
    fi
    echo "Removing stale build lock: $build_lock"
    rm -f "$build_lock"
fi

printf '%s\n' "$$" > "$create_lock"

restore_previous_latest() {
    [ "$build_attempted" = "1" ] || return 0
    [ "$build_verified" = "0" ] || return 0

    if [ -n "$previous_latest_target" ] &&
       [ -s "$project_dir/output/$previous_latest_target" ]; then
        ln -sfn "$previous_latest_target" "$latest_iso"
        previous_checksum="$project_dir/output/${previous_latest_target}.sha256"
        if [ -s "$previous_checksum" ]; then
            cp -f "$previous_checksum" "${latest_iso}.sha256"
        else
            rm -f "${latest_iso}.sha256"
        fi
        echo "Build was not verified; restored previous ISO: $previous_latest_target" >&2
    else
        rm -f "$latest_iso" "${latest_iso}.sha256"
        echo "Build was not verified; no previous ISO was available to restore." >&2
    fi
}

cleanup_create() {
    status=$?
    trap - EXIT HUP INT TERM
    rm -f "$create_lock"
    if [ -n "$snapshot_path" ]; then
        rm -f "$snapshot_path"
    fi
    if ! restore_previous_latest; then
        echo "Warning: could not restore the previous latest-ISO state." >&2
        status=1
    fi
    if [ -n "$apparmor_original" ]; then
        if ! sudo sysctl -q -w "$apparmor_key=$apparmor_original"; then
            echo "Warning: could not restore $apparmor_key=$apparmor_original" >&2
            status=1
        fi
    fi
    exit "$status"
}
trap cleanup_create EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Authenticate once before cleanup and namespace setup. The project itself is
# still built as the regular user; sudo is restricted to mount cleanup, stale
# root-owned artifacts and the temporary user-namespace sysctl.
sudo -v

apparmor_original=$(sysctl -n "$apparmor_key" 2>/dev/null || true)
case "$apparmor_original" in
    0) ;;
    1)
        echo "Temporarily enabling unprivileged user namespaces for the rootless build."
        sudo sysctl -q -w "$apparmor_key=0"
        ;;
    '')
        # Non-Ubuntu kernels may not expose this AppArmor setting.
        ;;
    *)
        echo "Unexpected $apparmor_key value: $apparmor_original" >&2
        exit 1
        ;;
esac

# Refuse to destroy the tree below a genuinely running low-level build. Normal
# create.sh concurrency is already covered by .create.lock; this catches a
# manually launched scripts/build.sh as well.
if lock_is_active "$build_lock"; then
    echo "A build became active during startup (PID $(cat "$build_lock"))." >&2
    exit 1
fi

unmount_tree() {
    tree=$1
    test -e "$tree" || return 0
    findmnt -R -rn -o TARGET "$tree" 2>/dev/null \
        | awk '{ print length($0), $0 }' \
        | LC_ALL=C sort -rn \
        | cut -d' ' -f2- \
        | while IFS= read -r mount_path
          do
              test -n "$mount_path" || continue
              sudo mount --make-private "$mount_path" 2>/dev/null || true
              sudo umount -l "$mount_path" 2>/dev/null || true
          done
}

reset_build_state() {
    builder_root=${AILINUX_BUILDER_CACHE:-"$HOME/.cache/ailinux-distro-builder"}/resolute-rootfs

    echo "Resetting previous AILinuX build state ..."

    # Remove only QEMU instances that reference this project's output. Other
    # libvirt/QEMU guests on the host are not touched.
    for pid in $(pgrep -f "qemu-system-x86_64.*$project_dir/output/" 2>/dev/null || true); do
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        echo "Stopping stale project QEMU process: $pid"
        kill "$pid" 2>/dev/null || true
    done

    unmount_tree "$project_dir/chroot"
    unmount_tree "$project_dir/binary"
    unmount_tree "$project_dir/cache"
    unmount_tree "$builder_root/workspace"
    unmount_tree "$builder_root/dev"
    unmount_tree "$builder_root/proc"
    unmount_tree "$builder_root/sys"

    # These are live-build products, never source inputs. sudo handles remnants
    # created by an older accidental root build without changing source owners.
    sudo rm -rf \
        "$project_dir/.build" \
        "$project_dir/.build.lock" \
        "$project_dir/.offline-build-state" \
        "$project_dir/binary" \
        "$project_dir/chroot" \
        "$project_dir/local"

    sudo rm -f \
        "$project_dir"/binary.contents \
        "$project_dir"/binary.packages \
        "$project_dir"/chroot.headers \
        "$project_dir"/chroot.packages.install \
        "$project_dir"/chroot.packages.live \
        "$project_dir"/ailinux-26.04-amd64-*.iso \
        "$project_dir"/live-image-amd64*.iso \
        "$project_dir"/config/ailinux-kernel.env.tmp.*

    sudo rm -f \
        "$project_dir"/output/create-current.*

    sudo chown "$(id -u):$(id -g)" "$project_dir/output"
    chmod 0755 "$project_dir/output"

    echo "Previous build tree removed; package cache and ISO artifacts preserved."
}

reset_build_state

# Verify that the host now permits the namespace mechanism before a lengthy
# package/build run begins.
if ! unshare --user --map-root-user --map-auto true; then
    echo "Rootless user namespaces are still unavailable on this host." >&2
    exit 1
fi

./scripts/prepare-infinity-theme.sh
./scripts/validate-project.sh

if [ "$AILINUX_RESET_ONLY" = "1" ]; then
    echo "Reset-only mode complete. No ISO build was started."
    exit 0
fi

echo "AILinuX clean ISO build"
echo "Project: $project_dir"
if [ "$AILINUX_PURGE_CACHE" = "1" ]; then
    echo "Mode: reset build tree and purge the downloaded package cache"
else
    echo "Mode: reset build tree and retain the validated package cache"
fi
if [ "$AILINUX_OFFLINE" = "1" ]; then
    echo "Repository mode: local AILinuX packages; official Ubuntu mirrors"
else
    echo "Repository mode: refresh AILinuX metadata online"
fi

# Online builds purge live-build stage/package caches by default so a clean
# build cannot silently inherit an older chroot or boot tree. Cache reuse is an
# explicit speed optimization (AILINUX_PURGE_CACHE=0); offline mode requires it.
build_attempted=1
./scripts/build-rootless.sh

test -L "$latest_iso" || {
    echo "Build finished without the latest-ISO symlink." >&2
    exit 1
}
test -s "$latest_iso"
(cd "$project_dir/output" && sha256sum --check "$(basename "$latest_iso.sha256")")

for firmware_mode in bios uefi; do
    for media_mode in cdrom usb; do
        AILINUX_QEMU_MODE="$firmware_mode" \
            AILINUX_QEMU_MEDIA="$media_mode" \
            ./scripts/smoke-test-iso.sh "$latest_iso"
    done
done

verified_target=$(readlink "$latest_iso")
case "$verified_target" in
    ''|*/*)
        echo "Latest-ISO symlink has an unsafe target: $verified_target" >&2
        exit 1
        ;;
esac
test -s "$project_dir/output/$verified_target"
ln -sfn "$verified_target" "$known_good_iso"
cp -f "${latest_iso}.sha256" "${known_good_iso}.sha256"
build_verified=1

echo "Verified ISO: $(readlink -f "$latest_iso")"
echo "Checksum: ${latest_iso}.sha256"
echo "Known-good ISO: $known_good_iso"
