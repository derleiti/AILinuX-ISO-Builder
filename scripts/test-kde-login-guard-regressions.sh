#!/bin/sh
# Isolated regression tests for version-based rejection paths only.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# The remainder of the hook needs a live SDDM/Wayland root filesystem;
# exercise only its package-version gate with injected dpkg-query outputs.
sed '/^# GDM3 can remain installed/,$d' "$project_dir/config/hooks/0196-qt-sddm-login-guard.chroot" > "$tmp/gate.sh"
printf '%s\n' 'echo VERSION_GATE_OK' >> "$tmp/gate.sh"
cat > "$tmp/dpkg-query" <<'MOCK'
#!/bin/sh
case "$4" in
    qt6-base) printf '%s' "$FAKE_QT" ;;
    kwin-wayland) printf '%s' "$FAKE_KWIN" ;;
    liblayershellqtinterface6) printf '%s' "$FAKE_LAYER" ;;
    qt6-wayland) printf '%s' "$FAKE_WAYLAND" ;;
    *) exit 1 ;;
esac
MOCK
# dpkg-query -W -f='${Version}' package: package is argument three.
sed -i 's/case "$4" in/case "$3" in/' "$tmp/dpkg-query"
chmod +x "$tmp/dpkg-query"
export PATH="$tmp:$PATH"
FAKE_QT='6.12.0-0zneon+26.04+resolute+stable+build20'
FAKE_KWIN='4:6.8.3-test'
FAKE_LAYER='6.8.2+p26.04+vstable+git20261027.1611-0'
FAKE_WAYLAND='6.12.0-0zneon+26.04+resolute+stable+build2'
export FAKE_QT FAKE_KWIN FAKE_LAYER FAKE_WAYLAND
if sh "$tmp/gate.sh" > "$tmp/out" 2>&1; then echo 'FAIL: known bad LayerShellQt pair accepted'; exit 1; fi
grep -q 'known-crashing LayerShellQt' "$tmp/out" || { cat "$tmp/out"; exit 1; }
echo 'PASS: observed lockscreen/logout crash combination rejected'
FAKE_LAYER='6.8.3-test'
FAKE_KWIN='4:6.8.2+p26.04+vstable+git20261028.0037-0'
export FAKE_LAYER FAKE_KWIN
if sh "$tmp/gate.sh" > "$tmp/out" 2>&1; then echo 'FAIL: old known-bad KWin pair accepted'; exit 1; fi
grep -q 'known-broken Qt/KWin login combination' "$tmp/out" || { cat "$tmp/out"; exit 1; }
echo 'PASS: existing KWin login regression protection retained'
FAKE_KWIN='4:6.8.3-test'
export FAKE_KWIN
sh "$tmp/gate.sh" > "$tmp/out" 2>&1
grep -q 'VERSION_GATE_OK' "$tmp/out" || { cat "$tmp/out"; exit 1; }
echo 'PASS: non-blacklisted version pair passes version gate'
FAKE_LAYER=''
export FAKE_LAYER
if sh "$tmp/gate.sh" > "$tmp/out" 2>&1; then echo 'FAIL: missing layer shell package accepted'; exit 1; fi
grep -q 'LayerShellQt or Qt Wayland package missing' "$tmp/out" || { cat "$tmp/out"; exit 1; }
echo 'PASS: missing LayerShellQt detected'
