#!/bin/bash
# Funktionstest fuer ailinux-verify-live-medium.
#
#   scripts/test-verify-live-medium.sh [MEDIUM]
#
# MEDIUM zeigt auf ein gemountetes Live-Medium mit casper/filesystem.squashfs
# und md5sum.txt. Das squashfs wird nie kopiert, sondern nur verlinkt; fuer den
# Fehlerfall wird stattdessen die erwartete Pruefsumme verfaelscht. Das spart
# mehrere Gigabyte pro Durchlauf und prueft denselben Codepfad.
set -u

MEDIUM=${1:-/cdrom}
SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/config/includes.chroot/usr/local/sbin/ailinux-verify-live-medium
BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

pass=0
fail=0

chk() {
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 (exit $3)"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1 (erwartet $2, war $3)"
        fail=$((fail + 1))
    fi
}

run() { AILINUX_LIVE_MEDIA="$1" "$SCRIPT" 2>&1; }

test -x "$SCRIPT" || { echo "Not executable: $SCRIPT" >&2; exit 1; }

SQUASHFS="$MEDIUM/casper/filesystem.squashfs"
SUMS="$MEDIUM/md5sum.txt"
test -f "$SQUASHFS" || { echo "No squashfs below $MEDIUM" >&2; exit 1; }
test -f "$SUMS" || { echo "No md5sum.txt below $MEDIUM" >&2; exit 1; }

for d in intact tampered nosums nosquashfs; do mkdir -p "$BASE/$d/casper"; done
ln -s "$SQUASHFS" "$BASE/intact/casper/filesystem.squashfs"
cp "$SUMS" "$BASE/intact/md5sum.txt"
ln -s "$SQUASHFS" "$BASE/tampered/casper/filesystem.squashfs"
sed 's|^[0-9a-f]*  \./casper/filesystem\.squashfs$|00000000000000000000000000000000  ./casper/filesystem.squashfs|' \
    "$SUMS" > "$BASE/tampered/md5sum.txt"
ln -s "$SQUASHFS" "$BASE/nosums/casper/filesystem.squashfs"

echo "Medium:   $MEDIUM"
echo "squashfs: $(stat -Lc %s "$SQUASHFS") Bytes"
echo

# Belegt nebenbei, dass die ISO in sich stimmig ist: die md5sum.txt des Builds
# passt zu dem squashfs, das danebenliegt.
echo "Fall A: intaktes Medium -> laeuft durch"
out=$(run "$BASE/intact"); rc=$?
echo "$out" | sed 's/^/  /'
chk "Fall A" 0 $rc
echo

echo "Fall B: Pruefsumme passt nicht -> harter Abbruch"
out=$(run "$BASE/tampered"); rc=$?
echo "$out" | sed 's/^/  /'
chk "Fall B" 1 $rc
echo

# Uebersprungen statt abgelehnt: Installationen aus anderen Quellen als einer
# gebauten ISO sollen weiter funktionieren.
echo "Fall C: keine md5sum.txt -> uebersprungen"
out=$(run "$BASE/nosums"); rc=$?
echo "$out" | sed 's/^/  /'
chk "Fall C" 0 $rc
echo

echo "Fall D: kein squashfs -> harter Abbruch"
out=$(run "$BASE/nosquashfs"); rc=$?
echo "$out" | sed 's/^/  /'
chk "Fall D" 1 $rc
echo

echo "Fall E: gar kein Medium -> uebersprungen"
out=$(run "$BASE/absent"); rc=$?
echo "$out" | sed 's/^/  /'
chk "Fall E" 0 $rc
echo

echo "================================"
echo "PASS: $pass   FAIL: $fail"
test "$fail" -eq 0
