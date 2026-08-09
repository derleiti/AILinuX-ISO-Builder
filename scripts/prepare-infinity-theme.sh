#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$project_dir/Theme/Infinity-Plasma-Themes"
target="$project_dir/config/includes.chroot"

need() {
    test -e "$1" || { echo "Missing Infinity theme component: $1" >&2; exit 1; }
}

for required in \
    "Infinity Global Themes" \
    "Infinity-Plasma-Themes" \
    "Infinity-Plasma-Splash-6" \
    "Infinity-SDDM" \
    "Infinity Color Schemes" \
    "Infinity-Icons" \
    "Infinity Windows Decorations" \
    "Infinity-Wallpapers" \
    "Infinity-GTK" \
    "Infinity Kvantum Theme"
do
    need "$source_dir/$required"
done

install_tree() {
    src=$1
    dst=$2
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

install_children() {
    src_root=$1
    dst_root=$2
    mkdir -p "$dst_root"
    find "$src_root" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r src
    do
        install_tree "$src" "$dst_root/$(basename "$src")"
    done
}

# Install every supplied Infinity variant so users can switch components later.
install_children "$source_dir/Infinity Global Themes" \
    "$target/usr/share/plasma/look-and-feel"
install_children "$source_dir/Infinity-Plasma-Themes" \
    "$target/usr/share/plasma/desktoptheme"
install_tree "$source_dir/Infinity-Plasma-Splash-6" \
    "$target/usr/share/plasma/look-and-feel/Infinity-Plasma-Splash-6"
install_children "$source_dir/Infinity-SDDM" \
    "$target/usr/share/sddm/themes"
install_children "$source_dir/Infinity-Icons" \
    "$target/usr/share/icons"
install_children "$source_dir/Infinity Windows Decorations" \
    "$target/usr/share/aurorae/themes"
install_children "$source_dir/Infinity-GTK" \
    "$target/usr/share/themes"
install_children "$source_dir/Infinity Kvantum Theme" \
    "$target/usr/share/Kvantum"

mkdir -p \
    "$target/usr/share/color-schemes" \
    "$target/usr/share/wallpapers/Infinity-World-Wallpaper/contents/images" \
    "$target/usr/share/wallpapers/Infinity-Originals" \
    "$target/etc/sddm.conf.d" \
    "$target/etc/xdg" \
    "$target/etc/skel/.config" \
    "$target/etc/skel/.config/Kvantum" \
    "$target/etc/skel/.config/gtk-3.0" \
    "$target/etc/skel/.config/gtk-4.0"

find "$source_dir/Infinity Color Schemes" -maxdepth 1 -type f -name '*.colors' \
    -exec install -m 0644 {} "$target/usr/share/color-schemes/" \;
find "$source_dir/Infinity-Wallpapers" -maxdepth 1 -type f \
    -exec install -m 0644 {} "$target/usr/share/wallpapers/Infinity-Originals/" \;

install -m 0644 "$source_dir/Infinity-Wallpapers/Infinity-World-Wallpaper Without Plasma logo.png" \
    "$target/usr/share/wallpapers/Infinity-World-Wallpaper/contents/images/3840x2160.png"

cat > "$target/etc/sddm.conf.d/20-ailinux-theme.conf" <<'CFG'
[Theme]
Current=Infinity-SDDM-6
CursorTheme=breeze_cursors
CFG

cat > "$target/etc/xdg/kdeglobals" <<'CFG'
[General]
ColorScheme=InfinityBlueDarkColor

[Icons]
Theme=Infinity-Dark-Icons

[KDE]
LookAndFeelPackage=Infinity-Global-6
widgetStyle=kvantum
CFG

cat > "$target/etc/xdg/plasmarc" <<'CFG'
[Theme]
name=Infinity-Plasma
CFG

cat > "$target/etc/xdg/ksplashrc" <<'CFG'
[KSplash]
Engine=KSplashQML
Theme=Infinity-Plasma-Splash-6
CFG

cat > "$target/etc/xdg/kwinrc" <<'CFG'
[org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=__aurorae__svg__Infinity-Color-Aurorae-6
CFG

cat > "$target/etc/xdg/gtk-3.0-settings.ini" <<'CFG'
[Settings]
gtk-theme-name=Infinity-GTK
gtk-icon-theme-name=Infinity-Dark-Icons
gtk-cursor-theme-name=breeze_cursors
gtk-application-prefer-dark-theme=true
CFG

cat > "$target/etc/xdg/gtk-4.0-settings.ini" <<'CFG'
[Settings]
gtk-theme-name=Infinity-GTK
gtk-icon-theme-name=Infinity-Dark-Icons
gtk-cursor-theme-name=breeze_cursors
gtk-application-prefer-dark-theme=true
CFG

cat > "$target/etc/xdg/Kvantum.kvconfig" <<'CFG'
[General]
theme=Infinity-Kvantum
CFG

cp -f "$target/etc/xdg/kdeglobals" "$target/etc/skel/.config/kdeglobals"
cp -f "$target/etc/xdg/plasmarc" "$target/etc/skel/.config/plasmarc"
cp -f "$target/etc/xdg/ksplashrc" "$target/etc/skel/.config/ksplashrc"
cp -f "$target/etc/xdg/kwinrc" "$target/etc/skel/.config/kwinrc"
cp -f "$target/etc/xdg/Kvantum.kvconfig" "$target/etc/skel/.config/Kvantum/kvantum.kvconfig"
cp -f "$target/etc/xdg/gtk-3.0-settings.ini" "$target/etc/skel/.config/gtk-3.0/settings.ini"
cp -f "$target/etc/xdg/gtk-4.0-settings.ini" "$target/etc/skel/.config/gtk-4.0/settings.ini"

mkdir -p "$target/etc/skel/.config/kdedefaults"
cp -f "$target/etc/xdg/kdeglobals" "$target/etc/skel/.config/kdedefaults/kdeglobals"
cp -f "$target/etc/xdg/plasmarc" "$target/etc/skel/.config/kdedefaults/plasmarc"
cp -f "$target/etc/xdg/ksplashrc" "$target/etc/skel/.config/kdedefaults/ksplashrc"
cp -f "$target/etc/xdg/kwinrc" "$target/etc/skel/.config/kdedefaults/kwinrc"
printf '%s\n' 'Infinity-Global-6' > "$target/etc/skel/.config/kdedefaults/package"

cat > "$target/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc" <<'CFG'
[Containments][1]
activityId=
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/Infinity-World-Wallpaper/contents/images/3840x2160.png
PreviewImage=file:///usr/share/wallpapers/Infinity-World-Wallpaper/contents/images/3840x2160.png
CFG

find \
    "$target/usr/share/plasma/look-and-feel" \
    "$target/usr/share/plasma/desktoptheme" \
    "$target/usr/share/sddm/themes" \
    "$target/usr/share/icons" \
    "$target/usr/share/aurorae/themes" \
    "$target/usr/share/themes" \
    "$target/usr/share/Kvantum" \
    -type d -exec chmod 0755 {} +
find \
    "$target/usr/share/plasma/look-and-feel" \
    "$target/usr/share/plasma/desktoptheme" \
    "$target/usr/share/sddm/themes" \
    "$target/usr/share/icons" \
    "$target/usr/share/aurorae/themes" \
    "$target/usr/share/themes" \
    "$target/usr/share/Kvantum" \
    -type f -exec chmod 0644 {} +

echo "Complete Infinity theme collection staged; dark Plasma 6 profile selected as default."
