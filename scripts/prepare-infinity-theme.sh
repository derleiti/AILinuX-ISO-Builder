#!/bin/sh
# Stage the checked-out Infinity suite into live-build's include tree without
# duplicating its roughly 500 MiB payload in this repository.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$project_dir/Infinity-Plasma-Themes"
include_root="$project_dir/config/includes.chroot"
state_dir="$project_dir/.infinity-theme-state"
manifest="$state_dir/paths"

usage() {
    echo "Usage: $0 {stage|cleanup}" >&2
    exit 2
}

remove_staged_paths() {
    [ -f "$manifest" ] || return 0
    while IFS= read -r relative_path; do
        case "$relative_path" in
            usr/share/color-schemes/InfinityBlueDarkColor.colors|\
            usr/share/Kvantum/Infinity-Kvantum|\
            usr/share/plasma/look-and-feel/Infinity-*|\
            usr/share/aurorae/themes/Infinity-*|\
            usr/share/themes/Infinity-*|\
            usr/share/icons/Infinity-*|\
            usr/share/plasma/desktoptheme/Infinity-*|\
            usr/share/sddm/themes/Infinity-*|\
            usr/share/wallpapers/Infinity-*)
                rm -rf -- "$include_root/$relative_path"
                ;;
            *)
                echo "Refusing unsafe Infinity staging path: $relative_path" >&2
                return 1
                ;;
        esac
    done < "$manifest"
}

cleanup() {
    remove_staged_paths
    rm -rf -- "$state_dir"
}

record_destination() {
    relative_path=$1
    [ ! -e "$include_root/$relative_path" ] || {
        echo "Infinity destination already exists: config/includes.chroot/$relative_path" >&2
        exit 1
    }
    printf '%s\n' "$relative_path" >> "$manifest"
}

copy_directory() {
    source_relative=$1
    destination_parent=$2
    source_path="$source_root/$source_relative"
    base_name=${source_path##*/}
    destination_relative="$destination_parent/$base_name"

    [ -d "$source_path" ] || {
        echo "Missing Infinity theme directory: $source_relative" >&2
        exit 1
    }
    record_destination "$destination_relative"
    mkdir -p "$include_root/$destination_parent"
    cp -a --reflink=auto "$source_path" "$include_root/$destination_parent/"
}

copy_file() {
    source_relative=$1
    destination_relative=$2
    source_path="$source_root/$source_relative"

    [ -s "$source_path" ] || {
        echo "Missing Infinity theme file: $source_relative" >&2
        exit 1
    }
    record_destination "$destination_relative"
    mkdir -p "$(dirname -- "$include_root/$destination_relative")"
    cp -a --reflink=auto "$source_path" "$include_root/$destination_relative"
}

stage_wallpaper() {
    wallpaper_id=$1
    source_name=$2
    metadata_name=$3
    destination_relative="usr/share/wallpapers/$wallpaper_id"

    record_destination "$destination_relative"
    mkdir -p "$include_root/$destination_relative/contents/images"
    cp -a --reflink=auto \
        "$source_root/Infinity-Wallpapers/$source_name" \
        "$include_root/$destination_relative/contents/images/1920x1080.png"
    cp -a --reflink=auto \
        "$project_dir/assets/infinity-theme/$metadata_name" \
        "$include_root/$destination_relative/metadata.json"
}

stage() {
    [ -d "$source_root" ] || {
        echo "Missing Infinity-Plasma-Themes checkout. Run: git submodule update --init" >&2
        exit 1
    }
    if [ -d "$state_dir" ]; then
        cleanup
    fi
    mkdir -p "$state_dir"
    : > "$manifest"
    trap 'cleanup; exit 129' HUP
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM

    copy_file "Infinity Color Schemes/InfinityBlueDarkColor.colors" \
        "usr/share/color-schemes/InfinityBlueDarkColor.colors"
    copy_directory "Infinity Kvantum Theme/Infinity-Kvantum" "usr/share/Kvantum"

    for theme in Infinity-Global Infinity-Global-6; do
        copy_directory "Infinity Global Themes/$theme" "usr/share/plasma/look-and-feel"
    done
    for theme in \
        Infinity-Blur-Aurorae Infinity-Blur-Aurorae-6 \
        Infinity-Color-Aurorae Infinity-Color-Aurorae-6 \
        Infinity-Solid-Aurorae Infinity-Solid-Aurorae-6
    do
        copy_directory "Infinity Windows Decorations/$theme" "usr/share/aurorae/themes"
    done
    for theme in Infinity-GTK Infinity-GTK-Light; do
        copy_directory "Infinity-GTK/$theme" "usr/share/themes"
    done
    for theme in \
        Infinity-Dark-Icons Infinity-Lavender-Dark-Icons \
        Infinity-Lavender-Light-Icons Infinity-Light-Icons
    do
        copy_directory "Infinity-Icons/$theme" "usr/share/icons"
    done
    copy_directory "Infinity-Plasma-Splash-6" "usr/share/plasma/look-and-feel"
    for theme in Infinity-Light-Plasma Infinity-Plasma Infinity-Solid-Plasma; do
        copy_directory "Infinity-Plasma-Themes/$theme" "usr/share/plasma/desktoptheme"
    done
    copy_directory "Infinity-SDDM/Infinity-SDDM-6" "usr/share/sddm/themes"

    stage_wallpaper \
        "Infinity-World-Wallpaper" \
        "Infinity-World-Wallpaper With Plasma logo.png" \
        "Infinity-World-Wallpaper.metadata.json"
    stage_wallpaper \
        "Infinity-World-Wallpaper-No-Logo" \
        "Infinity-World-Wallpaper Without Plasma logo.png" \
        "Infinity-World-Wallpaper-No-Logo.metadata.json"

    # The upstream Plasma 6 defaults use the old splash package ID and Breeze
    # widget style. Point the staged copy at the included Plasma 6 splash and
    # Kvantum theme while leaving the source checkout untouched.
    infinity_defaults="$include_root/usr/share/plasma/look-and-feel/Infinity-Global-6/contents/defaults"
    sed -i \
        -e 's/^widgetStyle=breeze$/widgetStyle=kvantum-dark/' \
        -e 's/^Theme=Infinity-Plasma-Splash$/Theme=Infinity-Plasma-Splash-6/' \
        "$infinity_defaults"

    trap - HUP INT TERM
    echo "Infinity theme suite staged for live-build."
}

case "${1:-}" in
    stage) stage ;;
    cleanup) cleanup ;;
    *) usage ;;
esac
