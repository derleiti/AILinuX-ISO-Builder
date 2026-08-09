#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
iso_path=${1:-}
timeout_seconds=${AILINUX_QEMU_TIMEOUT:-180}
firmware_mode=${AILINUX_QEMU_MODE:-bios}
media_mode=${AILINUX_QEMU_MEDIA:-cdrom}
firmware=
firmware_vars_template=
firmware_vars=
qemu_pid=

if [ -z "$iso_path" ]; then
    iso_path=$(find "$project_dir/output" -maxdepth 1 -type f \
        -name 'ailinux-26.04-amd64-*.iso' -printf '%T@ %p\n' |
        sort -nr | awk 'NR == 1 { print $2 }')
fi

test -r "$iso_path" || {
    echo "ISO not found: $iso_path" >&2
    exit 1
}

case "$timeout_seconds" in
    ''|*[!0-9]*)
        echo "AILINUX_QEMU_TIMEOUT must be an integer." >&2
        exit 1
        ;;
esac

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "qemu-system-x86_64 is required for the smoke test." >&2
    exit 1
}
command -v mktemp >/dev/null 2>&1 || {
    echo "mktemp is required for the UEFI smoke test." >&2
    exit 1
}

case "$firmware_mode" in
    bios) ;;
    uefi)
        firmware=${AILINUX_OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
        firmware_vars_template=${AILINUX_OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
        test -r "$firmware" || {
            echo "UEFI firmware code not found: $firmware" >&2
            exit 1
        }
        test -r "$firmware_vars_template" || {
            echo "UEFI firmware variables template not found: $firmware_vars_template" >&2
            exit 1
        }
        ;;
    *)
        echo "Unsupported AILINUX_QEMU_MODE: $firmware_mode" >&2
        exit 1
        ;;
esac

case "$media_mode" in
    cdrom|usb) ;;
    *)
        echo "Unsupported AILINUX_QEMU_MEDIA: $media_mode" >&2
        exit 1
        ;;
esac

"$project_dir/scripts/validate-iso-boot.sh" "$iso_path"

serial_log="$project_dir/output/qemu-$firmware_mode-$media_mode-serial.log"
rm -f "$serial_log"

cleanup() {
    if [ -n "$qemu_pid" ] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    qemu_pid=
    if [ -n "$firmware_vars" ]; then
        rm -f "$firmware_vars"
        firmware_vars=
    fi
}
trap cleanup EXIT HUP INT TERM

set -- qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -m 4096 \
    -smp 4 \
    -display none \
    -serial "file:$serial_log" \
    -no-reboot

if [ "$media_mode" = "cdrom" ]; then
    set -- "$@" -boot d -cdrom "$iso_path"
else
    set -- "$@" \
        -device qemu-xhci,id=ailinux_xhci \
        -drive "if=none,id=ailinux_usb,format=raw,readonly=on,file=$iso_path" \
        -device usb-storage,drive=ailinux_usb,bus=ailinux_xhci.0,bootindex=1
fi

if [ "$firmware_mode" = "uefi" ]; then
    firmware_vars=$(mktemp "$project_dir/output/.ovmf-vars-${firmware_mode}-${media_mode}.XXXXXX")
    cp "$firmware_vars_template" "$firmware_vars"
    set -- "$@" \
        -drive "if=pflash,unit=0,format=raw,readonly=on,file=$firmware" \
        -drive "if=pflash,unit=1,format=raw,file=$firmware_vars"
fi

failure_pattern='kernel panic|not syncing|unable to mount root fs|vfs: cannot open root device|unknown-block|unable to find a medium containing a live file system|can.t open /root/dev/console|entered emergency mode|you need to load the kernel first|premature end of file|bad shim signature|verification failed|security violation|invalid magic number|failed to load (the )?(kernel|initrd)'
success_pattern='AILINUX_GRAPHICAL_READY'

"$@" &
qemu_pid=$!

elapsed=0
success=false
while kill -0 "$qemu_pid" 2>/dev/null; do
    if [ -s "$serial_log" ] && grep -Eqi "$failure_pattern" "$serial_log"; then
        echo "Boot failure detected in QEMU $firmware_mode/$media_mode serial output." >&2
        tail -n 120 "$serial_log" >&2 || true
        exit 1
    fi
    if [ -s "$serial_log" ] && grep -Eqi "$success_pattern" "$serial_log"; then
        success=true
        break
    fi
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ "$success" = true ]; then
    cleanup
    trap - EXIT HUP INT TERM
    echo "QEMU $firmware_mode smoke test reached the graphical live system."
    echo "Boot medium: $media_mode"
    exit 0
fi

if [ "$elapsed" -ge "$timeout_seconds" ]; then
    cleanup
    trap - EXIT HUP INT TERM
    echo "QEMU $firmware_mode/$media_mode did not reach the graphical live system within ${timeout_seconds}s." >&2
    tail -n 120 "$serial_log" >&2 || true
    exit 1
fi

set +e
wait "$qemu_pid" 2>/dev/null
status=$?
set -e
cleanup
trap - EXIT HUP INT TERM

test -s "$serial_log" || {
    echo "QEMU started, but no serial boot output was captured." >&2
    exit 1
}

if grep -Eqi "$failure_pattern" "$serial_log"; then
    echo "Boot failure detected in QEMU $firmware_mode/$media_mode serial output." >&2
    exit 1
fi

case "$status" in
    0) ;;
    *)
        echo "QEMU failed with status $status" >&2
        exit "$status"
        ;;
esac

echo "QEMU $firmware_mode/$media_mode exited before the graphical live system was reached." >&2
exit 1
