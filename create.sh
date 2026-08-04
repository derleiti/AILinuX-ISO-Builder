#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

# Default to building from the network: a fresh clone has no live-build package
# cache, so offline mode cannot stage the AILinuX kernel and copa packages and
# would produce an image without them. Set AILINUX_OFFLINE=1 on a machine that
# has the cache to build while repo.ailinux.me is unavailable.
AILINUX_OFFLINE=${AILINUX_OFFLINE:-0}
AILINUX_RESET_ONLY=${AILINUX_RESET_ONLY:-0}
case "$AILINUX_OFFLINE" in
    0|1) ;;
    *)
        echo "AILINUX_OFFLINE must be 0 or 1." >&2
        exit 1
        ;;
esac
case "$AILINUX_RESET_ONLY" in
    0|1) ;;
    *)
        echo "AILINUX_RESET_ONLY must be 0 or 1." >&2
        exit 1
        ;;
esac
export AILINUX_OFFLINE

lock_file="$project_dir/.build.lock"

active_build_pid() {
    test -s "$lock_file" || return 1
    pid=$(sed -n '1p' "$lock_file")
    case "$pid" in
        ''|0|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$pid" 2>/dev/null
}

clear_stale_build_lock() {
    test -e "$lock_file" || return 0
    if active_build_pid; then
        echo "Build already active with PID $pid: $lock_file" >&2
        exit 1
    fi
    rm -f "$lock_file"
    echo "Removed stale build lock: $lock_file"
}

reset_build_state() {
    clear_stale_build_lock

    # A clean create must never publish an ISO left by an earlier failed build.
    # The reusable rootless builder lives below ~/.cache and is intentionally
    # retained; only live-build's project-local state and published artifacts
    # are removed here.
    rm -rf \
        .build \
        binary \
        cache \
        chroot \
        local \
        .downloads \
        .offline-build-state \
        output
    rm -f \
        binary.contents \
        binary.packages \
        chroot.headers \
        chroot.packages.* \
        .final-iso \
        .autologin-final-iso
    mkdir -p output
    echo "Previous build tree and ISO artifacts removed."
}

check_rootless_user_namespace() {
    if unshare --user --map-root-user --map-auto true >/dev/null 2>&1; then
        return 0
    fi

    restriction=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)
    if [ "$restriction" = "1" ]; then
        echo "Rootless build blocked by kernel.apparmor_restrict_unprivileged_userns=1." >&2
        echo "Temporarily enable it with:" >&2
        echo "  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0" >&2
    else
        echo "Rootless user namespaces are unavailable; check unshare and /etc/subuid." >&2
    fi
    exit 1
}

clear_stale_build_lock

if [ "$AILINUX_RESET_ONLY" = "1" ]; then
    reset_build_state
    exit 0
fi

echo "AILinuX clean ISO build"
echo "Project: $project_dir"
echo "Mode: clean live-build tree and package cache"
if [ "$AILINUX_OFFLINE" = "1" ]; then
    echo "Repository mode: local AILinuX packages; official Ubuntu mirrors"
else
    echo "Repository mode: refresh AILinuX metadata online"
fi

./scripts/validate-project.sh
reset_build_state
check_rootless_user_namespace

verified=0
cleanup_unverified_output() {
    status=$1
    trap - EXIT HUP INT TERM
    if [ "$verified" -ne 1 ]; then
        rm -f \
            "$project_dir"/output/ailinux-26.04-amd64-*.iso \
            "$project_dir"/output/ailinux-26.04-amd64-*.iso.sha256
        echo "Unverified ISO artifacts removed after build failure." >&2
    fi
    exit "$status"
}
trap 'cleanup_unverified_output "$?"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# build.sh interprets this as `lb clean --purge`, so no previous chroot,
# binary tree or downloaded live-build package cache is reused. The rootless
# wrapper may retain only its isolated Resolute builder environment.
AILINUX_PURGE_CACHE=1 ./scripts/build-rootless.sh

latest_iso="$project_dir/output/ailinux-26.04-amd64-latest.iso"
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

verified=1
trap - EXIT HUP INT TERM

echo "Verified ISO: $(readlink -f "$latest_iso")"
echo "Checksum: $latest_iso.sha256"
