#!/bin/bash
# Funktionstest fuer ailinux-verify-target-kernel.
#
# Der Fehler, den das Skript abfaengt, laesst sich nicht bequem herbeifuehren:
# er braucht einen Ventoy-Stick, der beim Entpacken zu wenig Bytes liefert.
# Deshalb wird das Ergebnis nachgestellt statt die Ursache - ein Zielbaum mit
# absichtlich zu kurzen Dateien reicht, um jeden Pfad des Skripts zu belegen.
#
#   scripts/test-verify-target-kernel.sh [MEDIUM]
#
# MEDIUM zeigt auf ein entpacktes oder gemountetes Live-Medium und braucht
# casper/vmlinuz-<version>. Liegt zusaetzlich casper/filesystem.squashfs
# daneben, laufen auch die Faelle fuer den bootkritischen Dateibaum.
set -u

MEDIUM=${1:-/cdrom}
SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/config/includes.chroot/usr/local/sbin/ailinux-verify-target-kernel
BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

pass=0
fail=0
skip=0

check() {
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 (exit $3)"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1 (erwartet $2, war $3)"
        fail=$((fail + 1))
    fi
}

assert() {
    if [ "$2" = "true" ]; then
        echo "  PASS  $1"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1"
        fail=$((fail + 1))
    fi
}

test -x "$SCRIPT" || { echo "Not executable: $SCRIPT" >&2; exit 1; }

GOOD=$(ls "$MEDIUM"/casper/vmlinuz-* 2>/dev/null | head -1) || true
test -n "${GOOD:-}" || { echo "No casper/vmlinuz-* below $MEDIUM" >&2; exit 1; }
VERSION=${GOOD##*/vmlinuz-}
SIZE=$(stat -c %s "$GOOD")

echo "Medium:         $MEDIUM"
echo "Referenzkernel: vmlinuz-$VERSION ($SIZE Bytes)"
echo

fresh() {
    rm -rf "$BASE/root" "$BASE/medium"
    mkdir -p "$BASE/root/boot" "$BASE/medium/casper"
}

run() {
    AILINUX_LIVE_MEDIA="$1" "$SCRIPT" "$BASE/root" 2>&1
}

# --- Kernel: Erkennung und Reparatur -------------------------------------

echo "Fall 1: Kernel zu kurz, Medium vorhanden -> Reparatur"
fresh
cp "$GOOD" "$BASE/medium/casper/vmlinuz-$VERSION"
head -c $((SIZE - 4000000)) "$GOOD" > "$BASE/root/boot/vmlinuz-$VERSION"
out=$(run "$BASE/medium"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 1 exit" 0 $rc
cmp -s "$GOOD" "$BASE/root/boot/vmlinuz-$VERSION" && r=true || r=false
assert "Fall 1 Kernel byte-identisch wiederhergestellt" "$r"
echo

echo "Fall 2: Kernel zu kurz, kein Medium -> harter Abbruch"
fresh
head -c $((SIZE - 4000000)) "$GOOD" > "$BASE/root/boot/vmlinuz-$VERSION"
out=$(run "$BASE/fehlt"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 2 exit" 1 $rc
echo

echo "Fall 3: Kernel vollstaendig -> unveraendert"
fresh
cp "$GOOD" "$BASE/medium/casper/vmlinuz-$VERSION"
cp "$GOOD" "$BASE/root/boot/vmlinuz-$VERSION"
out=$(run "$BASE/medium"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 3 exit" 0 $rc
case "$out" in *"restored 0 from the live medium"*) assert "Fall 3 keine Reparatur" true ;;
               *) assert "Fall 3 keine Reparatur" false ;; esac
echo

# Der Schaden, an dem die Installation real gescheitert ist: rsync --sparse legt
# den Nullbereich am Dateiende als Loch ab. Die Groesse bleibt exakt richtig,
# deshalb sieht ihn weder ein Groessenvergleich noch die Setup-Header-Arithmetik.
# Auf btrfs liefert GRUB ab dem Loch nichts mehr -> "premature end of file".
echo "Fall 3b: Loch bei korrekter Groesse -> aufgefuellt"
fresh
cp "$GOOD" "$BASE/medium/casper/vmlinuz-$VERSION"
cp --sparse=never "$GOOD" "$BASE/root/boot/vmlinuz-$VERSION"
if command -v fallocate >/dev/null 2>&1; then
    target="$BASE/root/boot/vmlinuz-$VERSION"
    size_before=$(stat -c %s "$target")
    # Loch auf Blockgrenze im hinteren Bereich, wie rsync es anlegen wuerde.
    hole_off=$(( (size_before - 8192) / 4096 * 4096 ))
    fallocate --punch-hole --keep-size -o "$hole_off" -l 4096 "$target" 2>/dev/null
    hole_at=$(python3 -c "import os,sys;fd=os.open(sys.argv[1],os.O_RDONLY);print(os.lseek(fd,0,os.SEEK_HOLE))" "$target" 2>/dev/null || echo "")
    if [ -n "$hole_at" ] && [ "$hole_at" -lt "$size_before" ]; then
        out=$(run "$BASE/medium"); rc=$?
        echo "$out" | sed 's/^/  /'
        check "Fall 3b exit" 0 $rc
        size_after=$(stat -c %s "$target")
        hole_after=$(python3 -c "import os,sys;fd=os.open(sys.argv[1],os.O_RDONLY);print(os.lseek(fd,0,os.SEEK_HOLE))" "$target")
        if [ "$size_after" = "$size_before" ] && [ "$hole_after" = "$size_after" ]; then
            assert "Fall 3b Loch aufgefuellt, Groesse unveraendert" true
        else
            assert "Fall 3b Loch aufgefuellt, Groesse unveraendert" false
        fi
        case "$out" in *"Refilling"*) assert "Fall 3b meldet die Reparatur" true ;;
                       *) assert "Fall 3b meldet die Reparatur" false ;; esac
    else
        echo "  SKIP  Fall 3b (Dateisystem legt hier kein Loch an)"
        skip=$((skip + 3))
    fi
else
    echo "  SKIP  Fall 3b (fallocate fehlt)"
    skip=$((skip + 3))
fi


echo "Fall 4: kein Kernel im Ziel -> harter Abbruch"
fresh
cp "$GOOD" "$BASE/medium/casper/vmlinuz-$VERSION"
out=$(run "$BASE/medium"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 4 exit" 1 $rc
echo

echo "Fall 5: Medium traegt selbst einen kaputten Kernel -> harter Abbruch"
fresh
head -c $((SIZE - 8000000)) "$GOOD" > "$BASE/medium/casper/vmlinuz-$VERSION"
head -c $((SIZE - 4000000)) "$GOOD" > "$BASE/root/boot/vmlinuz-$VERSION"
out=$(run "$BASE/medium"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 5 exit" 1 $rc
echo

# Genau hier kippt GRUB: ein einziges fehlendes Byte gegenueber dem, was der
# bzImage-Header ankuendigt, reicht fuer "premature end of file".
echo "Fall 6: exakt ein Byte zu kurz -> harter Abbruch"
fresh
head -c $((SIZE - 1)) "$GOOD" > "$BASE/root/boot/vmlinuz-$VERSION"
out=$(run "$BASE/fehlt"); rc=$?
echo "$out" | sed 's/^/  /'
check "Fall 6 exit" 1 $rc
echo

# --- Bootkritischer Dateibaum --------------------------------------------

SQUASHFS="$MEDIUM/casper/filesystem.squashfs"
if [ ! -f "$SQUASHFS" ] || ! command -v unsquashfs >/dev/null 2>&1; then
    echo "Faelle 7-9 uebersprungen: $SQUASHFS oder unsquashfs fehlt."
    skip=3
else
    echo "Baue groessengetreuen Zielbaum aus dem squashfs-Listing ..."
    fresh
    cp "$GOOD" "$BASE/medium/casper/vmlinuz-$VERSION"
    ln -s "$SQUASHFS" "$BASE/medium/casper/filesystem.squashfs"

    unsquashfs -ll "$SQUASHFS" boot usr/lib/modules 2>/dev/null | awk '
        $1 ~ /^-/ {
            p = $6
            for (i = 7; i <= NF; i++) p = p " " $i
            sub(/^squashfs-root\/?/, "", p)
            if (p != "") printf "%s\t%s\n", $3, p
        }
    ' > "$BASE/ref.txt"

    awk -F '\t' '{ n = split($2, a, "/"); d = ""; for (i = 1; i < n; i++) d = d a[i] "/"; if (d != "") print d }' \
        "$BASE/ref.txt" | sort -u | (cd "$BASE/root" && xargs -d '\n' mkdir -p)
    # Sparse angelegt: geprueft wird die Groesse, nicht der Inhalt.
    awk -F '\t' -v b="$BASE/root" '{ print $1" "b"/"$2 }' "$BASE/ref.txt" |
        while read -r sz path; do truncate -s "$sz" "$path"; done
    cp "$GOOD" "$BASE/root/boot/vmlinuz-$VERSION"
    echo "  $(wc -l < "$BASE/ref.txt") Referenzdateien angelegt."
    echo

    echo "Fall 7: Baum vollstaendig -> laeuft durch"
    out=$(run "$BASE/medium"); rc=$?
    echo "$out" | sed 's/^/  /' | head -5
    check "Fall 7 exit" 0 $rc
    echo

    echo "Fall 8: ein Modul abgeschnitten -> harter Abbruch"
    victim=$(find "$BASE/root/usr/lib/modules" -type f -size +100k | head -1)
    truncate -s 1024 "$victim"
    out=$(run "$BASE/medium"); rc=$?
    echo "$out" | sed 's/^/  /' | head -4
    check "Fall 8 exit" 1 $rc
    echo

    echo "Fall 9: ein Modul fehlt -> harter Abbruch"
    truncate -s "$(awk -F '\t' -v v="${victim#"$BASE/root/"}" '$2 == v { print $1 }' "$BASE/ref.txt")" "$victim"
    rm -f "$(find "$BASE/root/usr/lib/modules" -type f -name '*.ko*' | head -1)"
    out=$(run "$BASE/medium"); rc=$?
    echo "$out" | sed 's/^/  /' | head -4
    check "Fall 9 exit" 1 $rc
    echo
fi

echo "================================"
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
test "$fail" -eq 0
