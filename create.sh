#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

# A clean build must remain possible while repo.ailinux.me is unavailable.
# Set AILINUX_OFFLINE=0 explicitly to refresh kernel/repository metadata online.
AILINUX_OFFLINE=${AILINUX_OFFLINE:-1}
case "$AILINUX_OFFLINE" in
    0|1) ;;
    *)
        echo "AILINUX_OFFLINE must be 0 or 1." >&2
        exit 1
        ;;
esac
export AILINUX_OFFLINE

if [ -e .build.lock ]; then
    echo "Build already active: $project_dir/.build.lock" >&2
    exit 1
fi

echo "AILinuX clean ISO build"
echo "Project: $project_dir"
echo "Mode: clean live-build tree and package cache"
if [ "$AILINUX_OFFLINE" = "1" ]; then
    echo "Repository mode: local AILinuX packages; official Ubuntu mirrors"
else
    echo "Repository mode: refresh AILinuX metadata online"
fi

./scripts/validate-project.sh

# build.sh interprets this as `lb clean --purge`, so no previous chroot,
# binary tree or downloaded live-build package cache is reused. The rootless
# wrapper may retain only its isolated Resolute builder environment.
AILINUX_PURGE_CACHE=1 ./scripts/build-rootless.sh

latest_iso="$project_dir/output/ailinux-26.04-amd64-latest.iso"
test -L "$latest_iso" || {
    echo "Build finished without the latest-ISO symlink." >&2
    exit 1
}
test -s "$latest_iso"
(cd "$project_dir/output" && sha256sum --check "$(basename "$latest_iso.sha256")")

AILINUX_ISO="$latest_iso" ./scripts/smoke-test-iso.sh

echo "Verified ISO: $(readlink -f "$latest_iso")"
echo "Checksum: $latest_iso.sha256"
