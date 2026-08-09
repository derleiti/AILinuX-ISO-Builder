#!/bin/sh
set -eu

mode=${1:-rootless}
missing=

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        missing="$missing $1"
    fi
}

report_missing() {
    test -z "$missing" && return 0
    echo "Missing $mode dependencies:$missing" >&2
    return 1
}

case "$mode" in
    rootless)
        for tool in \
            unshare apt-get dpkg-deb python3 sha256sum readlink stat \
            awk sed grep find sort install mktemp
        do
            require_command "$tool"
        done
        report_missing || exit 1

        ubuntu_keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
        test -r "$ubuntu_keyring" || {
            echo "Ubuntu archive keyring is required: $ubuntu_keyring" >&2
            echo "On Ubuntu, install it with: sudo apt-get install ubuntu-keyring" >&2
            exit 1
        }

        if ! unshare --user --map-root-user --map-auto true >/dev/null 2>&1; then
            restriction=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)
            if [ "$restriction" = "1" ]; then
                echo "Rootless build blocked by kernel.apparmor_restrict_unprivileged_userns=1." >&2
                echo "Temporarily enable it with:" >&2
                echo "  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0" >&2
            else
                current_user=$(id -un 2>/dev/null || true)
                echo "Rootless user namespaces with subordinate IDs are unavailable." >&2
                if [ -n "$current_user" ] && \
                    { ! grep -q "^${current_user}:" /etc/subuid 2>/dev/null || \
                      ! grep -q "^${current_user}:" /etc/subgid 2>/dev/null; }
                then
                    echo "Add subordinate UID/GID ranges for $current_user, then log in again:" >&2
                    echo "  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $current_user" >&2
                else
                    echo "Check whether unprivileged user namespaces are disabled by the host or container." >&2
                fi
            fi
            exit 1
        fi

        echo "Rootless build preflight passed."
        ;;
    smoke)
        for tool in qemu-system-x86_64 xorriso grep awk mktemp; do
            require_command "$tool"
        done
        report_missing || exit 1

        firmware=${AILINUX_OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
        test -r "$firmware" || {
            echo "UEFI firmware is required for smoke tests: $firmware" >&2
            echo "On Ubuntu, install it with: sudo apt-get install ovmf" >&2
            exit 1
        }

        echo "QEMU smoke-test preflight passed."
        ;;
    *)
        echo "Usage: $0 {rootless|smoke}" >&2
        exit 2
        ;;
esac
