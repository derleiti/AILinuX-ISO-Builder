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
AILINUX_SMOKE_TESTS=${AILINUX_SMOKE_TESTS:-auto}
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
case "$AILINUX_SMOKE_TESTS" in
    auto|0|1) ;;
    *)
        echo "AILINUX_SMOKE_TESTS must be auto, 0 or 1." >&2
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

acquire_build_lock() {
    attempts=0
    while [ "$attempts" -lt 2 ]; do
        if (set -C; printf '%s\n' "$$" > "$lock_file") 2>/dev/null; then
            return 0
        fi
        if active_build_pid; then
            echo "Build already active with PID $pid: $lock_file" >&2
            exit 1
        fi
        rm -f "$lock_file"
        echo "Removed stale build lock: $lock_file"
        attempts=$((attempts + 1))
    done
    echo "Unable to acquire build lock: $lock_file" >&2
    exit 1
}

release_build_lock() {
    test -s "$lock_file" || return 0
    lock_pid=$(sed -n '1p' "$lock_file")
    if [ "$lock_pid" = "$$" ]; then
        rm -f "$lock_file"
    fi
}

reset_build_state() {
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

manage_output=0
artifact_ready=0
finish() {
    status=$1
    trap - EXIT HUP INT TERM
    if [ "$manage_output" -eq 1 ] && [ "$artifact_ready" -ne 1 ]; then
        rm -f \
            "$project_dir"/output/ailinux-26.04-amd64-*.iso \
            "$project_dir"/output/ailinux-26.04-amd64-*.iso.sha256
        echo "Incomplete ISO artifacts removed after build failure." >&2
    elif [ "$manage_output" -eq 1 ] && [ "$artifact_ready" -eq 1 ] && [ "$status" -ne 0 ]; then
        echo "The structurally verified ISO was retained despite a later test failure." >&2
    fi
    release_build_lock
    exit "$status"
}
trap 'finish "$?"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_build_lock
AILINUX_BUILD_LOCK_PID=$$
export AILINUX_BUILD_LOCK_PID

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

./scripts/preflight-build.sh rootless
./scripts/validate-project.sh

run_smoke_tests=0
case "$AILINUX_SMOKE_TESTS" in
    1)
        ./scripts/preflight-build.sh smoke
        run_smoke_tests=1
        ;;
    auto)
        if smoke_preflight=$(./scripts/preflight-build.sh smoke 2>&1); then
            echo "$smoke_preflight"
            run_smoke_tests=1
        else
            echo "QEMU smoke tests skipped automatically:"
            printf '%s\n' "$smoke_preflight" | sed 's/^/  /'
            echo "Set AILINUX_SMOKE_TESTS=1 to require them."
        fi
        ;;
    0)
        echo "QEMU smoke tests disabled (AILINUX_SMOKE_TESTS=0)."
        ;;
esac

reset_build_state
manage_output=1

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
artifact_ready=1

if [ "$run_smoke_tests" -eq 1 ]; then
    for firmware_mode in bios uefi; do
        for media_mode in cdrom usb; do
            AILINUX_QEMU_MODE="$firmware_mode" \
                AILINUX_QEMU_MEDIA="$media_mode" \
                ./scripts/smoke-test-iso.sh "$latest_iso"
        done
    done
fi

echo "Created and structurally verified ISO: $(readlink -f "$latest_iso")"
if [ "$run_smoke_tests" -eq 1 ]; then
    echo "QEMU verification: BIOS/UEFI and CD-ROM/USB passed."
else
    echo "QEMU verification: skipped."
fi
echo "Checksum: $latest_iso.sha256"
