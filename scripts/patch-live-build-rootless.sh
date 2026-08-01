#!/bin/sh
set -eu

target=${AILINUX_LIVE_BUILD_SYSFS_SCRIPT:-/usr/lib/live/build/lb_chroot_sysfs}
archives_target=${AILINUX_LIVE_BUILD_ARCHIVES_SCRIPT:-/usr/lib/live/build/lb_chroot_archives}
devpts_target=${AILINUX_LIVE_BUILD_DEVPTS_SCRIPT:-/usr/lib/live/build/lb_chroot_devpts}
binary_chroot_target=${AILINUX_LIVE_BUILD_BINARY_CHROOT_SCRIPT:-/usr/lib/live/build/lb_binary_chroot}
original='${LB_ROOT_COMMAND} mount sysfs-live -t sysfs chroot/sys'
test "$(id -u)" -eq 0 || {
    echo "The live-build namespace patch must run as namespace root." >&2
    exit 1
}
test -f "$target" || {
    echo "Unsupported live-build installation: $target is missing." >&2
    exit 1
}
test -f "$archives_target" || {
    echo "Unsupported live-build installation: $archives_target is missing." >&2
    exit 1
}
test -f "$devpts_target" || {
    echo "Unsupported live-build installation: $devpts_target is missing." >&2
    exit 1
}
test -f "$binary_chroot_target" || {
    echo "Unsupported live-build installation: $binary_chroot_target is missing." >&2
    exit 1
}

if ! grep -Fq 'mount --rbind /sys chroot/sys' "$target"; then
    grep -Fq "$original" "$target" || {
        echo "Unsupported live-build sysfs implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/mount sysfs-live -t sysfs chroot\/sys/c\
			${LB_ROOT_COMMAND} mount --rbind /sys chroot/sys\
			${LB_ROOT_COMMAND} mount --make-rslave chroot/sys' "$target"
fi
grep -Fq 'mount --rbind /sys chroot/sys' "$target"

if ! grep -Fq 'AILINUX_ROOTLESS_SYSFS_CLEANUP' "$target"; then
    grep -Fq '				do_umount chroot/sys' "$target" || {
        echo "Unsupported live-build sysfs cleanup implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/				do_umount chroot\/sys/c\
				# AILINUX_ROOTLESS_SYSFS_CLEANUP\
				${LB_ROOT_COMMAND} mount --make-rprivate chroot/sys || true\
				${LB_ROOT_COMMAND} umount -R chroot/sys || true' "$target"
fi
grep -Fq 'AILINUX_ROOTLESS_SYSFS_CLEANUP' "$target"
if ! grep -Fq 'AILINUX_ROOTLESS_SYSFS_CLEANUP_V2' "$target"; then
    if ! grep -Fq '${LB_ROOT_COMMAND} umount -R -l chroot/sys' "$target"; then
        sed -i 's@${LB_ROOT_COMMAND} umount -R chroot/sys || true@${LB_ROOT_COMMAND} umount -R -l chroot/sys || true@' "$target"
    fi
    grep -Fq '${LB_ROOT_COMMAND} umount -R -l chroot/sys' "$target"
fi

if ! grep -Fq 'AILINUX_LOCAL_ARCHIVE_KEYS' "$archives_target"; then
    grep -Fq '		# Check local pinning preferences' "$archives_target" || {
        echo "Unsupported live-build archive implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/		# Check local pinning preferences/i\
		# AILINUX_LOCAL_ARCHIVE_KEYS: old live-build copies local lists but not their keys.\
		for KEY in config/archives/*.key config/archives/*.key.chroot\
		do\
			if [ -e "${KEY}" ]\
			then\
				KEY_NAME=$(basename "${KEY}")\
				KEY_NAME=${KEY_NAME%.chroot}\
				KEY_NAME=${KEY_NAME%.key}.gpg\
				cp "${KEY}" "chroot/etc/apt/trusted.gpg.d/${KEY_NAME}"\
			fi\
		done\
' "$archives_target"
fi
grep -Fq 'AILINUX_LOCAL_ARCHIVE_KEYS' "$archives_target"

if ! grep -Fq 'AILINUX_LOCAL_REPOSITORY_GNUPG' "$archives_target"; then
    grep -Fq '				# Generate Packages and Packages.gz' "$archives_target" || {
        echo "Unsupported live-build local repository implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/				# Generate Packages and Packages.gz/i\
				# AILINUX_LOCAL_REPOSITORY_GNUPG: required to sign config/packages.chroot.\
				Apt chroot install gnupg\
' "$archives_target"
fi
grep -Fq 'AILINUX_LOCAL_REPOSITORY_GNUPG' "$archives_target"

if ! grep -Fq '%no-protection # AILINUX_GNUPG2' "$archives_target"; then
    grep -Fq '						      %commit" | Chroot chroot "gpg --batch --gen-key"' "$archives_target" || {
        echo "Unsupported live-build GnuPG implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/						      %commit" | Chroot chroot "gpg --batch --gen-key"/i\
						      %no-protection # AILINUX_GNUPG2' "$archives_target"
fi
grep -Fq '%no-protection # AILINUX_GNUPG2' "$archives_target"

if ! grep -Fq 'AILINUX_TRUST_LOCAL_PACKAGES' "$archives_target"; then
    sed -i 's/				if \[ "${LB_APT_SECURE}" = "true" \]/				if false # AILINUX_TRUST_LOCAL_PACKAGES/' "$archives_target"
    sed -i 's|deb file:/root/packages \./|deb [trusted=yes] file:/root/packages ./|' "$archives_target"
fi
grep -Fq 'if false # AILINUX_TRUST_LOCAL_PACKAGES' "$archives_target"
grep -Fq 'deb [trusted=yes] file:/root/packages ./' "$archives_target"

if ! grep -Fq 'AILINUX_ROOTLESS_DEV' "$devpts_target"; then
    grep -Fq '			# Creating mountpoint' "$devpts_target" || {
        echo "Unsupported live-build devpts implementation; refusing to patch." >&2
        exit 1
    }
    sed -i '/			# Creating mountpoint/i\
			# AILINUX_ROOTLESS_DEV: debootstrap cannot create device nodes in this user namespace.\
			${LB_ROOT_COMMAND} mount --rbind /dev chroot/dev\
			${LB_ROOT_COMMAND} mount --make-rslave chroot/dev\
' "$devpts_target"
    sed -i '/		# Removing stage file/i\
		if grep -qs "$(pwd)/chroot/dev " /proc/mounts\
		then\
			${LB_ROOT_COMMAND} umount -R chroot/dev\
		fi\
' "$devpts_target"
fi
grep -Fq 'AILINUX_ROOTLESS_DEV' "$devpts_target"

if ! grep -Fq 'AILINUX_ROOTLESS_DEV_CLEANUP' "$devpts_target"; then
    sed -i 's@				${LB_ROOT_COMMAND} umount chroot/dev/pts$@				${LB_ROOT_COMMAND} umount chroot/dev/pts || true # AILINUX_ROOTLESS_DEV_CLEANUP@' "$devpts_target"
    sed -i '/			${LB_ROOT_COMMAND} umount -R chroot\/dev/c\
			${LB_ROOT_COMMAND} mount --make-rprivate chroot/dev || true\
			${LB_ROOT_COMMAND} umount -R chroot/dev || true' "$devpts_target"
fi
grep -Fq 'AILINUX_ROOTLESS_DEV_CLEANUP' "$devpts_target"
if ! grep -Fq 'AILINUX_ROOTLESS_DEV_TREE_CLEANUP_V2' "$devpts_target"; then
    if ! grep -Fq '${LB_ROOT_COMMAND} umount -R -l chroot/dev' "$devpts_target"; then
        sed -i 's@${LB_ROOT_COMMAND} umount -R chroot/dev || true@${LB_ROOT_COMMAND} umount -R -l chroot/dev || true@' "$devpts_target"
    fi
    grep -Fq '${LB_ROOT_COMMAND} umount -R -l chroot/dev' "$devpts_target"
fi

if ! grep -Fq 'AILINUX_BINARY_CHROOT_SYSFS_CLEANUP' "$binary_chroot_target"; then
    grep -Fq '		${LB_ROOT_COMMAND} umount chroot/sys' "$binary_chroot_target" || {
        echo "Unsupported live-build binary chroot cleanup; refusing to patch." >&2
        exit 1
    }
    sed -i '/		${LB_ROOT_COMMAND} umount chroot\/sys/c\
		# AILINUX_BINARY_CHROOT_SYSFS_CLEANUP\
		${LB_ROOT_COMMAND} umount -R -l chroot/sys || true' "$binary_chroot_target"
fi
grep -Fq 'AILINUX_BINARY_CHROOT_SYSFS_CLEANUP' "$binary_chroot_target"

echo "Patched live-build for rootless sysfs, /dev, and local archives."
