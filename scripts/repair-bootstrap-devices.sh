#!/bin/sh
set -eu

devdir=${1:-cache/bootstrap/dev}
[ -d "$devdir" ] || exit 0
[ "$(id -u)" -eq 0 ] || { echo "Bootstrap device repair must run as root." >&2; exit 1; }

make_dev() {
    name=$1 mode=$2 major=$3 minor=$4
    path="$devdir/$name"
    if [ ! -c "$path" ]; then
        rm -f "$path"
        mknod -m "$mode" "$path" c "$major" "$minor"
        chown root:root "$path"
        echo "Repaired bootstrap device: /dev/$name ($major,$minor)"
    fi
}

make_dev null    666 1 3
make_dev zero    666 1 5
make_dev full    666 1 7
make_dev random  666 1 8
make_dev urandom 666 1 9
make_dev tty     666 5 0
make_dev console 600 5 1
