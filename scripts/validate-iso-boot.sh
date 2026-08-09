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
boot_lba_report="$work_dir/boot-lba-report.txt"

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

# Some UEFI optical implementations become unreliable when GRUB has to fetch
# the kernel or initrd from very late ISO blocks. Keep both completely inside
# the first 2 GiB and reject regressions before QEMU or real-hardware testing.
xorriso -indev "$iso_path" -find /casper -type f -exec report_lba -- >"$boot_lba_report" 2>/dev/null
if ! awk -F',' -v limit=1048576 '
    /\/casper\/vmlinuz-/ {
        kernels++
        if (($2 + 0) + ($3 + 0) > limit) bad = 1
    }
    /\/casper\/initrd\.img-/ {
        initrds++
        if (($2 + 0) + ($3 + 0) > limit) bad = 1
    }
    END { exit(kernels > 0 && initrds > 0 && !bad ? 0 : 1) }
' "$boot_lba_report"; then
    echo "Kernel or initrd is outside the first 2 GiB of the ISO; UEFI optical boot is unsafe." >&2
    grep -E '/casper/(vmlinuz-|initrd\.img-)' "$boot_lba_report" >&2 || true
    exit 1
fi

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
if grep -Eq '(^|[[:space:]])debug=1([[:space:]]|$)' "$grub_cfg"; then
    echo "GRUB enables initramfs debug mode for the normal hardware boot." >&2
    exit 1
fi
if ! awk '
    /^[[:space:]]*linux[[:space:]]/ {
        quiet = 0
        splash = 0
        for (i = 1; i <= NF; i++) {
            if ($i == "quiet") quiet = 1
            if ($i == "splash") splash = 1
        }
        if (quiet && splash) production = 1
    }
    END { exit(production ? 0 : 1) }
' "$grub_cfg"; then
    echo "GRUB has no production live entry with quiet/splash enabled." >&2
    exit 1
fi
if ! awk '
    /^[[:space:]]*linux[[:space:]]/ {
        serial = 0
        screen = 0
        for (i = 1; i <= NF; i++) {
            if ($i == "console=ttyS0,115200n8") serial = i
            if ($i == "console=tty0") screen = i
        }
        count++
        if (!serial || !screen || screen < serial) bad = 1
    }
    END { exit(count > 0 && !bad ? 0 : 1) }
' "$grub_cfg"; then
    echo "GRUB must keep serial diagnostics but select tty0 as the final hardware console." >&2
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
