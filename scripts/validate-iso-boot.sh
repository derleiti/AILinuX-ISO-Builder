#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
iso_path=${1:-"$project_dir/output/ailinux-26.04-amd64-latest.iso"}

test -r "$iso_path" || {
    echo "ISO not found: $iso_path" >&2
    exit 1
}

for tool in xorriso grep awk mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool is required for ISO boot validation." >&2
        exit 1
    }
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ailinux-iso-boot.XXXXXX")
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

boot_report="$work_dir/boot-report.txt"
casper_listing="$work_dir/casper-listing.txt"
grub_cfg="$work_dir/grub.cfg"

xorriso -indev "$iso_path" -report_el_torito plain -report_system_area plain >"$boot_report" 2>&1

grep -Eq '^Volume id[[:space:]]*: .AILINUX_2604.' "$boot_report" || {
    echo "ISO volume ID is not AILINUX_2604." >&2
    exit 1
}
grep -Eq '^El Torito boot img :.* BIOS[[:space:]]+y[[:space:]]' "$boot_report" || {
    echo "ISO has no bootable El Torito BIOS image." >&2
    exit 1
}
grep -Eq '^El Torito boot img :.* UEFI[[:space:]]+y[[:space:]]' "$boot_report" || {
    echo "ISO has no bootable El Torito UEFI image." >&2
    exit 1
}
grep -Eq '^Boot record[[:space:]]*:.*El Torito.*MBR.*GPT' "$boot_report" || {
    echo "ISO is not a BIOS/UEFI hybrid image with MBR and GPT metadata." >&2
    exit 1
}

xorriso -indev "$iso_path" -ls /casper >"$casper_listing" 2>&1
for pattern in 'filesystem.squashfs' 'initrd.img-' 'vmlinuz-'; do
    grep -Fq "$pattern" "$casper_listing" || {
        echo "Missing required /casper artifact: $pattern" >&2
        exit 1
    }
done

xorriso -osirrox on -indev "$iso_path" -extract /boot/grub/grub.cfg "$grub_cfg" >/dev/null 2>&1

grep -Fq '# AILINUX_SEARCH_ROOT' "$grub_cfg"
grep -Fq 'search --no-floppy --set=root --label AILINUX_2604' "$grub_cfg"
grep -Fq 'search --no-floppy --set=root --file /.disk/info' "$grub_cfg"

if grep -Eq '(^|[[:space:]])boot=live([[:space:]]|$)' "$grub_cfg"; then
    echo "GRUB contains boot=live, but the Ubuntu initramfs provides casper." >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])live-media=' "$grub_cfg"; then
    echo "GRUB pins a live-media device, which breaks Ventoy media discovery." >&2
    exit 1
fi

awk '
    /^[[:space:]]*linux[[:space:]]/ {
        count++
        if ($0 !~ /\/casper\/vmlinuz-/ ||
            $0 !~ /(^|[[:space:]])boot=casper([[:space:]]|$)/) {
            bad = 1
        }
    }
    END { exit(count > 0 && !bad ? 0 : 1) }
' "$grub_cfg" || {
    echo "A GRUB kernel entry is not a casper live entry." >&2
    exit 1
}

awk '
    /^[[:space:]]*initrd[[:space:]]/ {
        count++
        if ($0 !~ /\/casper\/initrd\.img-/) {
            bad = 1
        }
    }
    END { exit(count > 0 && !bad ? 0 : 1) }
' "$grub_cfg" || {
    echo "A GRUB initrd entry does not reference /casper." >&2
    exit 1
}

echo "ISO boot structure passed: BIOS, UEFI, hybrid USB and Ventoy media discovery."
