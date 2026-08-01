#!/bin/sh
# Read-only audit of an installed AILinuX target filesystem.
#
# Usage: verify-installed-system.sh ROOT [USERNAME]
#
# ROOT must be the mounted target root (for example /mnt/ailinux).  USERNAME is
# optional; without it, the lowest numbered regular /home user is selected.
# A live-build chroot intentionally has no such user.  In that case the image
# payload is checked, while installed-user, desktop and generated-GRUB checks
# are reported as SKIP instead of being credited as successful installation
# checks.

set -u

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
export LC_ALL

usage() {
    echo "Usage: $0 ROOT [USERNAME]" >&2
    exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage

root_input=$1
requested_user=${2:-}

[ -d "$root_input" ] || {
    echo "Target root is not a directory: $root_input" >&2
    exit 2
}

root=$(CDPATH= cd -- "$root_input" 2>/dev/null && pwd -P) || {
    echo "Cannot resolve target root: $root_input" >&2
    exit 2
}

[ -f "$root/etc/os-release" ] || {
    echo "Target does not look like a Linux root (missing /etc/os-release): $root" >&2
    exit 2
}

passes=0
warnings=0
skips=0
failures=0

pass() {
    passes=$((passes + 1))
    printf 'PASS: %s\n' "$*"
}

warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$*" >&2
}

skip() {
    skips=$((skips + 1))
    printf 'SKIP: %s\n' "$*"
}

fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$*" >&2
}

os_release_value() {
    awk -v wanted="$1" '
        index($0, wanted "=") == 1 {
            value = substr($0, length(wanted) + 2)
            if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                value = substr(value, 2, length(value) - 2)
            }
            print value
            exit
        }
    ' "$root/etc/os-release"
}

package_installed() {
    awk -v wanted="$1" '
        BEGIN { RS = ""; FS = "\n"; found = 0 }
        {
            package = ""
            status = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package = substr($i, 10)
                if ($i ~ /^Status: /) status = substr($i, 9)
            }
            if (package == wanted && status == "install ok installed") found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$root/var/lib/dpkg/status"
}

package_field() {
    awk -v wanted="$1" -v wanted_field="$2" '
        BEGIN { RS = ""; FS = "\n" }
        {
            package = ""
            status = ""
            value = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package = substr($i, 10)
                if ($i ~ /^Status: /) status = substr($i, 9)
                if (index($i, wanted_field ": ") == 1) {
                    value = substr($i, length(wanted_field) + 3)
                }
            }
            if (package == wanted && status == "install ok installed") {
                print value
                exit
            }
        }
    ' "$root/var/lib/dpkg/status"
}

ini_value() {
    ini_file=$1
    ini_section=$2
    ini_key=$3

    [ -f "$ini_file" ] || return 0
    awk -v wanted_section="$ini_section" -v wanted_key="$ini_key" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^[[:space:]]*\[/ {
            line = $0
            sub(/^[[:space:]]*\[/, "", line)
            sub(/\][[:space:]]*$/, "", line)
            section = trim(line)
            next
        }
        section == wanted_section && index($0, "=") > 0 {
            line = $0
            key = line
            sub(/=.*/, "", key)
            key = trim(key)
            if (key == wanted_key) {
                sub(/^[^=]*=/, "", line)
                value = trim(line)
            }
        }
        END { if (value != "") print value }
    ' "$ini_file"
}

check_ini_value() {
    check_label=$1
    check_file=$2
    check_section=$3
    check_key=$4
    check_expected=$5
    check_actual=$(ini_value "$check_file" "$check_section" "$check_key")

    if [ "$check_actual" = "$check_expected" ]; then
        pass "$check_label ($check_key=$check_expected)"
    elif [ -z "$check_actual" ]; then
        fail "$check_label: missing [$check_section] $check_key in ${check_file#$root}"
    else
        fail "$check_label: expected $check_key=$check_expected, found $check_actual"
    fi
}

printf 'AILinuX installed-system audit\n'
printf 'Target: %s\n\n' "$root"

# Distribution identity and KDE System Information logo.
os_id=$(os_release_value ID)
os_name=$(os_release_value NAME)
os_logo=$(os_release_value LOGO)

[ "$os_id" = "ailinux" ] && pass 'OS ID is ailinux' || fail "OS ID is not ailinux (found: ${os_id:-missing})"
[ "$os_name" = "AILinuX" ] && pass 'OS name is AILinuX' || fail "OS name is not AILinuX (found: ${os_name:-missing})"
[ "$os_logo" = "ailinux-logo" ] && pass 'os-release selects ailinux-logo' || fail "LOGO is not ailinux-logo (found: ${os_logo:-missing})"

for logo_size in 32 48 64 128 256 512; do
    logo_file="$root/usr/share/icons/hicolor/${logo_size}x${logo_size}/apps/ailinux-logo.png"
    if [ -s "$logo_file" ]; then
        pass "AILinuX KDE logo ${logo_size}x${logo_size} is installed"
    else
        fail "missing AILinuX KDE logo: ${logo_file#$root}"
    fi
done

# The package database under ROOT is read directly; no package operation and
# no target command is run here.
status_file="$root/var/lib/dpkg/status"
if [ ! -r "$status_file" ]; then
    fail 'dpkg status database is missing or unreadable'
    package_db=false
else
    package_db=true
    pass 'dpkg status database is readable'
fi

# AILinuX kernel, matching initramfs and module tree.
kernel_count=0
for kernel_file in "$root"/boot/vmlinuz-*-ailinux; do
    [ -f "$kernel_file" ] || continue
    kernel_count=$((kernel_count + 1))
    kernel_version=${kernel_file##*/vmlinuz-}
    modules_dir="$root/lib/modules/$kernel_version"
    initrd_file="$root/boot/initrd.img-$kernel_version"

    [ -s "$kernel_file" ] && pass "AILinuX kernel image $kernel_version is present" || fail "empty kernel image: ${kernel_file#$root}"
    [ -s "$initrd_file" ] && pass "matching initramfs for $kernel_version is present" || fail "missing initramfs for $kernel_version"
    [ -d "$modules_dir" ] && pass "matching module tree for $kernel_version is present" || fail "missing module tree for $kernel_version"
    [ -s "$modules_dir/modules.dep" ] && pass "module dependency index for $kernel_version is present" || fail "missing modules.dep for $kernel_version"

    if [ "$package_db" = true ] && package_installed "linux-image-$kernel_version"; then
        pass "kernel package linux-image-$kernel_version is installed"
    elif [ "$package_db" = true ]; then
        fail "kernel files exist without installed dpkg package linux-image-$kernel_version"
    fi
done
[ "$kernel_count" -gt 0 ] || fail 'no /boot/vmlinuz-*-ailinux kernel was found'

if [ "$package_db" = true ]; then
    # Native Mozilla Firefox DEB, not Ubuntu's snap transition package.
    if package_installed firefox; then
        firefox_version=$(package_field firefox Version)
        firefox_description=$(package_field firefox Description)
        pass "native Firefox package is installed (${firefox_version:-unknown version})"
        case "$firefox_version $firefox_description" in
            *[Tt]ransitional*|*[Ss]nap*)
                fail "Firefox package looks like a snap transition: $firefox_version $firefox_description"
                ;;
            *) pass 'Firefox package metadata is not a snap transition' ;;
        esac
    else
        fail 'Firefox DEB package is not installed'
    fi

    if [ -x "$root/usr/lib/firefox/firefox-bin" ] && \
       grep -Fxq '/usr/lib/firefox/firefox-bin' "$root/var/lib/dpkg/info/firefox.list" 2>/dev/null; then
        pass 'Firefox native executable is owned by the firefox DEB'
    else
        fail 'native /usr/lib/firefox/firefox-bin is missing or not owned by the firefox DEB'
    fi

    firefox_snap=
    if [ -d "$root/var/lib/snapd/snaps" ]; then
        firefox_snap=$(find "$root/var/lib/snapd/snaps" -maxdepth 1 -type f -name 'firefox_*.snap' -print -quit 2>/dev/null)
    fi
    if [ -n "$firefox_snap" ] || [ -e "$root/snap/firefox" ] || [ -L "$root/snap/firefox" ]; then
        fail 'a Firefox snap is present alongside the native DEB'
    else
        pass 'no Firefox snap payload is present'
    fi

    # Ubuntu Server is the base; Plasma is layered explicitly on top.
    for required_package in ubuntu-server plasma-desktop plasma-workspace sddm; do
        if package_installed "$required_package"; then
            pass "required server/Plasma package is installed: $required_package"
        else
            fail "required server/Plasma package is missing: $required_package"
        fi
    done

    for oxygen_package in kde-style-oxygen-qt6 kwin-decoration-oxygen oxygen-sounds plasma-theme-oxygen; do
        if package_installed "$oxygen_package"; then
            pass "required Oxygen package is installed: $oxygen_package"
        else
            fail "required Oxygen package is missing: $oxygen_package"
        fi
    done

    kubuntu_packages=$(awk '
        BEGIN { RS = ""; FS = "\n" }
        {
            package = ""
            status = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package = substr($i, 10)
                if ($i ~ /^Status: /) status = substr($i, 9)
            }
            if (status == "install ok installed" && tolower(package) ~ /kubuntu/) print package
        }
    ' "$status_file")
    if [ -z "$kubuntu_packages" ]; then
        pass 'no installed Kubuntu-named packages were found'
    else
        fail "Kubuntu packages are installed: $(printf '%s' "$kubuntu_packages" | tr '\n' ' ')"
    fi
fi

# Determine whether this is an installed target or the prepared live/build
# filesystem.  An explicit USERNAME always requests installed-user checks.
passwd_file="$root/etc/passwd"
selected_user=
user_home=
user_uid=
user_gid=
mode=installed

if [ -n "$requested_user" ]; then
    case "$requested_user" in
        *[!a-zA-Z0-9_.-]*|'')
            fail "invalid requested user name: $requested_user"
            ;;
        *)
            selected_user=$requested_user
            user_record=$(awk -F: -v wanted="$selected_user" '$1 == wanted { print; exit }' "$passwd_file" 2>/dev/null)
            if [ -z "$user_record" ]; then
                fail "requested user does not exist in target: $selected_user"
                selected_user=
            fi
            ;;
    esac
else
    user_candidates=$(awk -F: '
        $3 >= 1000 && $3 < 60000 && $6 ~ /^\/home\// && $7 !~ /(nologin|false)$/ {
            print $1 ":" $3 ":" $4 ":" $6
        }
    ' "$passwd_file" 2>/dev/null | sort -t: -k2,2n)
    candidate_count=$(printf '%s\n' "$user_candidates" | awk 'NF { count++ } END { print count + 0 }')
    if [ "$candidate_count" -eq 0 ]; then
        mode=live-build
    else
        selected_user=$(printf '%s\n' "$user_candidates" | awk -F: 'NF { print $1; exit }')
        [ "$candidate_count" -eq 1 ] || warn "multiple regular users found; checking lowest UID user $selected_user (pass USERNAME to select another)"
    fi
fi

if [ -n "$selected_user" ]; then
    user_record=$(awk -F: -v wanted="$selected_user" '$1 == wanted { print; exit }' "$passwd_file")
    user_uid=$(printf '%s\n' "$user_record" | awk -F: '{ print $3 }')
    user_gid=$(printf '%s\n' "$user_record" | awk -F: '{ print $4 }')
    user_home=$(printf '%s\n' "$user_record" | awk -F: '{ print $6 }')
    pass "checking installed user $selected_user (UID $user_uid)"

    if [ -e "$root/run/live/medium" ] || [ -e "$root/lib/live/mount/medium" ]; then
        mode=live
        warn 'live-media markers are present; installed-user cleanup checks are skipped'
    fi
fi

printf '\nDetected target mode: %s\n' "$mode"

# Oxygen must be a default, not a forced login-time override.  Prefer an
# explicit user setting.  If the profile has not materialized it yet, verify
# the /etc/skel seed which Calamares copies when creating the user.
oxygen_config="$root/etc/skel/.config"
oxygen_origin='/etc/skel fallback'
if [ -n "$selected_user" ] && [ "$mode" = installed ]; then
    profile_config="$root$user_home/.config"
    profile_look=$(ini_value "$profile_config/kdeglobals" KDE LookAndFeelPackage)
    if [ -n "$profile_look" ]; then
        oxygen_config=$profile_config
        oxygen_origin="user profile $user_home"
    fi
fi

if [ -d "$oxygen_config" ]; then
    pass "Oxygen configuration source is $oxygen_origin"
    check_ini_value 'Oxygen global look-and-feel' "$oxygen_config/kdeglobals" KDE LookAndFeelPackage org.kde.oxygen
    check_ini_value 'Oxygen color scheme' "$oxygen_config/kdedefaults/kdeglobals" General ColorScheme Oxygen
    check_ini_value 'Oxygen icon theme' "$oxygen_config/kdedefaults/kdeglobals" Icons Theme oxygen
    check_ini_value 'Oxygen widget style' "$oxygen_config/kdedefaults/kdeglobals" KDE widgetStyle oxygen
    check_ini_value 'Oxygen cursor theme' "$oxygen_config/kdedefaults/kcminputrc" Mouse cursorTheme Oxygen_Black
    check_ini_value 'Oxygen splash theme' "$oxygen_config/kdedefaults/ksplashrc" KSplash Theme org.kde.oxygen
    check_ini_value 'Oxygen window decoration' "$oxygen_config/kdedefaults/kwinrc" org.kde.kdecoration2 library org.kde.oxygen
    check_ini_value 'Oxygen Plasma theme' "$oxygen_config/kdedefaults/plasmarc" Theme name oxygen
else
    fail 'neither installed-user nor /etc/skel Oxygen configuration is available'
fi

if [ ! -d "$root/usr/share/plasma/look-and-feel/org.kde.oxygen" ]; then
    fail 'Oxygen look-and-feel package data is missing'
else
    pass 'Oxygen look-and-feel package data is present'
fi

# GRUB defaults can be checked in both image and installed targets.
grub_defaults="$root/etc/default/grub.d/99-ailinux.cfg"
check_ini_value 'GRUB distributor' "$grub_defaults" '' GRUB_DISTRIBUTOR '"AILinuX"'
check_ini_value 'GRUB visible menu' "$grub_defaults" '' GRUB_TIMEOUT_STYLE menu
check_ini_value 'GRUB menu timeout' "$grub_defaults" '' GRUB_TIMEOUT 10
check_ini_value 'GRUB flat kernel list' "$grub_defaults" '' GRUB_DISABLE_SUBMENU y
check_ini_value 'GRUB recovery entries enabled' "$grub_defaults" '' GRUB_DISABLE_RECOVERY false
check_ini_value 'GRUB safe-mode title' "$grub_defaults" '' GRUB_RECOVERY_TITLE '"Safe Mode"'

if [ "$mode" = installed ] && [ -n "$selected_user" ]; then
    # The target user's Desktop must be genuinely empty.  Check both KDE's
    # untranslated and German directory names, plus the system skeleton.
    if [ ! -d "$root$user_home" ]; then
        fail "installed user home is not mounted or missing: $user_home"
    else
        desktop_entry=$(find "$root$user_home" -mindepth 2 -maxdepth 2 \
            \( -path '*/Desktop/*' -o -path '*/Schreibtisch/*' \) -print -quit 2>/dev/null)
        if [ -z "$desktop_entry" ]; then
            pass "installed user desktop is empty: $user_home"
        else
            fail "installed user desktop is not empty: ${desktop_entry#$root}"
        fi
    fi

    skel_desktop_entry=$(find "$root/etc/skel" -mindepth 2 -maxdepth 2 \
        \( -path '*/Desktop/*' -o -path '*/Schreibtisch/*' \) -print -quit 2>/dev/null)
    [ -z "$skel_desktop_entry" ] && pass '/etc/skel contains no live desktop links' || fail "live desktop link remains in /etc/skel: ${skel_desktop_entry#$root}"

    for live_path in \
        /usr/share/applications/ailinux-installer.desktop \
        /usr/local/bin/ailinux-installer; do
        if [ -e "$root$live_path" ] || [ -L "$root$live_path" ]; then
            fail "live installer artifact remains in installed target: $live_path"
        else
            pass "live installer artifact was removed: $live_path"
        fi
    done

    # sudo group membership and explicit, validated Calamares drop-in.
    sudo_gid=$(awk -F: '$1 == "sudo" { print $3; exit }' "$root/etc/group")
    sudo_members=$(awk -F: '$1 == "sudo" { print $4; exit }' "$root/etc/group")
    in_sudo=false
    [ -n "$sudo_gid" ] && [ "$user_gid" = "$sudo_gid" ] && in_sudo=true
    if [ "$in_sudo" = false ] && printf '%s\n' "$sudo_members" | tr ',' '\n' | grep -Fxq "$selected_user"; then
        in_sudo=true
    fi
    [ "$in_sudo" = true ] && pass "$selected_user is a member of sudo" || fail "$selected_user is not a member of sudo"

    if grep -Eq '^[[:space:]]*%sudo[[:space:]]+ALL=' "$root/etc/sudoers" 2>/dev/null; then
        pass 'sudo group is authorized in /etc/sudoers'
    else
        fail 'sudo group is not authorized in /etc/sudoers'
    fi

    sudo_drop="$root/etc/sudoers.d/90-ailinux-installer-user"
    if [ -f "$sudo_drop" ]; then
        sudo_mode=$(stat -c '%a' "$sudo_drop" 2>/dev/null || true)
        [ "$sudo_mode" = 440 ] && pass 'installer sudoers drop-in has mode 0440' || fail "installer sudoers drop-in mode is ${sudo_mode:-unknown}, expected 0440"
        if grep -Fxq "$selected_user ALL=(ALL:ALL) ALL" "$sudo_drop"; then
            pass "installer sudoers drop-in explicitly authorizes $selected_user"
        else
            fail "installer sudoers drop-in does not contain the exact rule for $selected_user"
        fi

        if command -v visudo >/dev/null 2>&1; then
            if visudo -cf "$sudo_drop" >/dev/null 2>&1; then
                pass 'installer sudoers drop-in passes host visudo syntax validation'
            else
                fail 'installer sudoers drop-in fails host visudo syntax validation'
            fi
        else
            skip 'host visudo is unavailable; strict drop-in content was checked instead'
        fi
    else
        fail 'missing /etc/sudoers.d/90-ailinux-installer-user'
    fi

    if [ "$(id -u)" -eq 0 ] && command -v chroot >/dev/null 2>&1 && [ -x "$root/usr/sbin/visudo" ]; then
        if chroot "$root" /usr/sbin/visudo -cf /etc/sudoers >/dev/null 2>&1; then
            pass 'complete target sudoers policy passes target visudo validation'
        else
            fail 'complete target sudoers policy fails target visudo validation'
        fi
    else
        skip 'full sudoers validation needs root, chroot and target visudo'
    fi

    grub_cfg="$root/boot/grub/grub.cfg"
    if [ ! -r "$grub_cfg" ]; then
        fail 'installed target has no readable /boot/grub/grub.cfg'
    else
        for kernel_file in "$root"/boot/vmlinuz-*-ailinux; do
            [ -f "$kernel_file" ] || continue
            kernel_version=${kernel_file##*/vmlinuz-}
            if grep -F "AILinuX $kernel_version" "$grub_cfg" | grep -Fvq '(Safe Mode)'; then
                pass "GRUB has normal AILinuX entry for $kernel_version"
            else
                fail "GRUB lacks normal AILinuX entry for $kernel_version"
            fi
            if grep -Fq "AILinuX $kernel_version (Safe Mode)" "$grub_cfg"; then
                pass "GRUB has Safe Mode entry for $kernel_version"
            else
                fail "GRUB lacks Safe Mode entry for $kernel_version"
            fi
        done
    fi
elif [ "$mode" = live ]; then
    skip 'desktop, sudoers drop-in and installed GRUB checks do not apply to a live session'
else
    skip 'no regular installed user exists in this live/build root; desktop and sudo checks are not claimed'
    skip 'generated installed /boot/grub/grub.cfg is checked only after a Calamares installation'
fi

printf '\nSummary: %d PASS, %d WARN, %d SKIP, %d FAIL\n' "$passes" "$warnings" "$skips" "$failures"

if [ "$failures" -ne 0 ]; then
    exit 1
fi
exit 0
