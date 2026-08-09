#!/bin/sh
# Synchronize or verify the pinned Infinity source against the system-wide
# live-build include tree. Theme payloads are versioned and are never removed
# automatically after a build.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$project_dir/Infinity-Plasma-Themes"
include_root="$project_dir/config/includes.chroot"

usage() {
    echo "Usage: $0 {sync|verify}" >&2
    exit 2
}

require_source() {
    [ -d "$source_root" ] || {
        echo "Missing Infinity-Plasma-Themes checkout. Run: git submodule update --init" >&2
        exit 1
    }
}

sync_directory() {
    source_relative=$1
    destination_parent=$2
    source_path="$source_root/$source_relative"

    [ -d "$source_path" ] || {
        echo "Missing Infinity theme directory: $source_relative" >&2
        exit 1
    }
    mkdir -p "$include_root/$destination_parent"
    cp -a --reflink=auto "$source_path" "$include_root/$destination_parent/"
}

sync_file() {
    source_relative=$1
    destination_relative=$2
    source_path="$source_root/$source_relative"

    [ -s "$source_path" ] || {
        echo "Missing Infinity theme file: $source_relative" >&2
        exit 1
    }
    mkdir -p "$(dirname -- "$include_root/$destination_relative")"
    cp -a --reflink=auto "$source_path" "$include_root/$destination_relative"
}

sync_wallpaper() {
    wallpaper_id=$1
    source_name=$2
    metadata_name=$3
    destination="$include_root/usr/share/wallpapers/$wallpaper_id"

    mkdir -p "$destination/contents/images"
    cp -a --reflink=auto \
        "$source_root/Infinity-Wallpapers/$source_name" \
        "$destination/contents/images/1920x1080.png"
    cp -a --reflink=auto \
        "$project_dir/assets/infinity-theme/$metadata_name" \
        "$destination/metadata.json"
}

sync_themes() {
    require_source

    sync_file "Infinity Color Schemes/InfinityBlueDarkColor.colors" \
        "usr/share/color-schemes/InfinityBlueDarkColor.colors"
    sync_directory "Infinity Kvantum Theme/Infinity-Kvantum" "usr/share/Kvantum"

    for theme in Infinity-Global Infinity-Global-6; do
        sync_directory "Infinity Global Themes/$theme" "usr/share/plasma/look-and-feel"
    done
    for theme in \
        Infinity-Blur-Aurorae Infinity-Blur-Aurorae-6 \
        Infinity-Color-Aurorae Infinity-Color-Aurorae-6 \
        Infinity-Solid-Aurorae Infinity-Solid-Aurorae-6
    do
        sync_directory "Infinity Windows Decorations/$theme" "usr/share/aurorae/themes"
    done
    for theme in Infinity-GTK Infinity-GTK-Light; do
        sync_directory "Infinity-GTK/$theme" "usr/share/themes"
    done
    for theme in \
        Infinity-Dark-Icons Infinity-Lavender-Dark-Icons \
        Infinity-Lavender-Light-Icons Infinity-Light-Icons
    do
        sync_directory "Infinity-Icons/$theme" "usr/share/icons"
    done
    sync_directory "Infinity-Plasma-Splash-6" "usr/share/plasma/look-and-feel"
    for theme in Infinity-Light-Plasma Infinity-Plasma Infinity-Solid-Plasma; do
        sync_directory "Infinity-Plasma-Themes/$theme" "usr/share/plasma/desktoptheme"
    done
    sync_directory "Infinity-SDDM/Infinity-SDDM-6" "usr/share/sddm/themes"

    sync_wallpaper \
        "Infinity-World-Wallpaper" \
        "Infinity-World-Wallpaper With Plasma logo.png" \
        "Infinity-World-Wallpaper.metadata.json"
    sync_wallpaper \
        "Infinity-World-Wallpaper-No-Logo" \
        "Infinity-World-Wallpaper Without Plasma logo.png" \
        "Infinity-World-Wallpaper-No-Logo.metadata.json"

    # Fix two upstream Plasma 6 references in the system-wide copy while the
    # pinned source checkout remains untouched.
    for infinity_defaults in \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global/contents/defaults" \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global-6/contents/defaults"
    do
        sed -i \
            -e 's/^widgetStyle=breeze$/widgetStyle=kvantum-dark/' \
            -e 's/^ColorScheme=InfinityDarkColor$/ColorScheme=InfinityBlueDarkColor/' \
            -e 's/^Image=Gently-Nebula-Noir Plasma Logo.jpg$/Image=Infinity-World-Wallpaper/' \
            -e 's/^Theme=Infinity-Plasma-Splash$/Theme=Infinity-Plasma-Splash-6/' \
            "$infinity_defaults"
    done

    echo "Infinity theme suite synchronized."
}

verify_themes() {
    require_source
    missing=0
    for relative_path in \
        usr/share/color-schemes/InfinityBlueDarkColor.colors \
        usr/share/Kvantum/Infinity-Kvantum/Infinity-Kvantum.kvconfig \
        usr/share/plasma/look-and-feel/Infinity-Global/metadata.desktop \
        usr/share/plasma/look-and-feel/Infinity-Global-6/metadata.json \
        usr/share/plasma/look-and-feel/Infinity-Plasma-Splash-6/metadata.json \
        usr/share/aurorae/themes/Infinity-Blur-Aurorae-6/metadata.json \
        usr/share/aurorae/themes/Infinity-Color-Aurorae-6/metadata.json \
        usr/share/aurorae/themes/Infinity-Solid-Aurorae-6/metadata.json \
        usr/share/themes/Infinity-GTK/gtk-3.0/gtk.css \
        usr/share/icons/Infinity-Dark-Icons/index.theme \
        usr/share/icons/Infinity-Lavender-Dark-Icons/index.theme \
        usr/share/icons/Infinity-Lavender-Light-Icons/index.theme \
        usr/share/icons/Infinity-Light-Icons/index.theme \
        usr/share/plasma/desktoptheme/Infinity-Plasma/metadata.desktop \
        usr/share/plasma/desktoptheme/Infinity-Solid-Plasma/metadata.desktop \
        usr/share/sddm/themes/Infinity-SDDM-6/Main.qml \
        usr/share/wallpapers/Infinity-World-Wallpaper/metadata.json \
        usr/share/wallpapers/Infinity-World-Wallpaper-No-Logo/metadata.json
    do
        if [ ! -s "$include_root/$relative_path" ]; then
            echo "Missing versioned Infinity asset: config/includes.chroot/$relative_path" >&2
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ] || exit 1
    grep -Fxq 'widgetStyle=kvantum-dark' \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global-6/contents/defaults"
    grep -Fxq 'ColorScheme=InfinityBlueDarkColor' \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global-6/contents/defaults"
    grep -Fxq 'ColorScheme=InfinityBlueDarkColor' \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global/contents/defaults"
    grep -Fxq 'Image=Infinity-World-Wallpaper' \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global/contents/defaults"
    grep -Fxq 'Theme=Infinity-Plasma-Splash-6' \
        "$include_root/usr/share/plasma/look-and-feel/Infinity-Global-6/contents/defaults"
    echo "Infinity theme suite verified."
}

case "${1:-}" in
    sync) sync_themes ;;
    verify) verify_themes ;;
    *) usage ;;
esac
