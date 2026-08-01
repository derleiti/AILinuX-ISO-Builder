#!/bin/sh
set -eu

test "$(id -u)" -eq 0 || {
    echo "The live-build mount patch must run as namespace root." >&2
    exit 1
}

base=${AILINUX_LIVE_BUILD_DIR:-/usr/lib/live/build}
helper="$base/ailinux-unmount-tree"

for name in lb_chroot_sysfs lb_chroot_devpts lb_chroot_proc lb_binary_chroot
do
    test -f "$base/$name" || {
        echo "Unsupported live-build installation: $base/$name is missing." >&2
        exit 1
    }
done

cat > "$helper" <<'HELPER'
#!/bin/sh
set -eu

target=${1:?mount tree path required}
mkdir -p "$target"
target_abs=$(readlink -f "$target" 2>/dev/null || realpath -m "$target")

# Detach deepest mounts first. /proc/self/mountinfo field 5 is the mount point.
awk -v root="$target_abs" '
    $5 == root || index($5, root "/") == 1 { print length($5), $5 }
' /proc/self/mountinfo \
    | LC_ALL=C sort -rn \
    | cut -d' ' -f2- \
    | while IFS= read -r mount_path
      do
          mount --make-private "$mount_path" 2>/dev/null || true
          umount -l "$mount_path" 2>/dev/null || true
      done

mount --make-rprivate "$target" 2>/dev/null || true
umount -R -l "$target" 2>/dev/null || true
umount -l "$target" 2>/dev/null || true

if mountpoint -q "$target"
then
    echo "Unable to detach mount tree: $target" >&2
    findmnt -R "$target" >&2 || true
    exit 1
fi

mkdir -p "$target"
HELPER
chmod 0755 "$helper"

python3 - "$base" <<'PY'
from pathlib import Path
import re
import sys

base = Path(sys.argv[1])
helper_call = '${LB_ROOT_COMMAND} /usr/lib/live/build/ailinux-unmount-tree'


def load(name: str) -> tuple[Path, str]:
    path = base / name
    return path, path.read_text()


def save(path: Path, text: str) -> None:
    path.write_text(text)


# sysfs: normalize the previously patched recursive unmount to the robust helper.
path, text = load('lb_chroot_sysfs')
text, count = re.subn(
    r'\t\t\t\t# AILINUX_ROOTLESS_SYSFS_CLEANUP(?:_V2)?\n'
    r'(?:\t\t\t\t.*\n){1,3}',
    '\t\t\t\t# AILINUX_ROOTLESS_SYSFS_CLEANUP_V2\n'
    f'\t\t\t\t{helper_call} chroot/sys\n',
    text,
    count=1,
)
if count == 0 and 'AILINUX_ROOTLESS_SYSFS_CLEANUP_V2' not in text:
    raise SystemExit('Could not patch lb_chroot_sysfs cleanup')
save(path, text)

# /dev: always detach the complete tree, rather than relying on an exact /proc/mounts string.
path, text = load('lb_chroot_devpts')
text, count = re.subn(
    r'\t\tif grep -qs "\$\(pwd\)/chroot/dev " /proc/mounts\n'
    r'\t\tthen\n'
    r'(?:\t\t\t.*\n){1,4}'
    r'\t\tfi\n',
    '\t\t# AILINUX_ROOTLESS_DEV_TREE_CLEANUP_V2\n'
    f'\t\t{helper_call} chroot/dev\n',
    text,
    count=1,
)
if count == 0 and 'AILINUX_ROOTLESS_DEV_TREE_CLEANUP_V2' not in text:
    raise SystemExit('Could not patch lb_chroot_devpts cleanup')
save(path, text)

# /proc can contain nested binfmt_misc mounts; detach it recursively too.
path, text = load('lb_chroot_proc')
if 'AILINUX_ROOTLESS_PROC_CLEANUP_V2' not in text:
    old = '\t\t\t\t${LB_ROOT_COMMAND} umount chroot/proc\n'
    new = (
        '\t\t\t\t# AILINUX_ROOTLESS_PROC_CLEANUP_V2\n'
        f'\t\t\t\t{helper_call} chroot/proc\n'
    )
    if old not in text:
        raise SystemExit('Could not patch lb_chroot_proc cleanup')
    text = text.replace(old, new, 1)
save(path, text)

# Before live-build copies the completed system into chroot/chroot, guarantee that
# no virtual filesystem is still attached to the source tree.
path, text = load('lb_binary_chroot')
if 'AILINUX_BINARY_CHROOT_PROC_CLEANUP_V2' not in text:
    text = text.replace(
        '\t\t${LB_ROOT_COMMAND} umount chroot/proc\n',
        '\t\t# AILINUX_BINARY_CHROOT_PROC_CLEANUP_V2\n'
        f'\t\t{helper_call} chroot/proc\n',
        1,
    )

text, count = re.subn(
    r'\t\t# AILINUX_BINARY_CHROOT_SYSFS_CLEANUP(?:_V2)?\n'
    r'(?:\t\t.*\n){1,3}',
    '\t\t# AILINUX_BINARY_CHROOT_SYSFS_CLEANUP_V2\n'
    f'\t\t{helper_call} chroot/sys\n',
    text,
    count=1,
)
if count == 0 and 'AILINUX_BINARY_CHROOT_SYSFS_CLEANUP_V2' not in text:
    raise SystemExit('Could not patch lb_binary_chroot sysfs cleanup')

if 'AILINUX_BINARY_CHROOT_DEV_CLEANUP_V2' not in text:
    marker = '# Copying /dev if using fakeroot\n'
    block = (
        '# AILINUX_BINARY_CHROOT_DEV_CLEANUP_V2\n'
        'if [ "${LB_USE_FAKEROOT}" != "true" ]\n'
        'then\n'
        f'\t{helper_call} chroot/dev\n'
        '\tmkdir -p chroot/dev chroot/proc chroot/sys chroot/run\n'
        'fi\n\n'
    )
    if marker not in text:
        raise SystemExit('Could not locate lb_binary_chroot /dev insertion point')
    text = text.replace(marker, block + marker, 1)
save(path, text)
PY

for marker in \
    AILINUX_ROOTLESS_SYSFS_CLEANUP_V2 \
    AILINUX_ROOTLESS_DEV_TREE_CLEANUP_V2 \
    AILINUX_ROOTLESS_PROC_CLEANUP_V2 \
    AILINUX_BINARY_CHROOT_DEV_CLEANUP_V2
do
    grep -R -Fq "$marker" "$base" || {
        echo "Mount cleanup marker missing: $marker" >&2
        exit 1
    }
done

echo "Patched live-build with robust recursive mount cleanup."
