#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
codename=${AILINUX_CODENAME:-resolute}
base_url=${AILINUX_REPO_BASE:-https://repo.ailinux.me/mirror}
include_root="$project_dir/config/includes.chroot"
source_dir="$include_root/etc/apt/sources.list.d"
manifest_copy="$project_dir/config/third-party-repos.json"
offline=${AILINUX_OFFLINE:-0}

case "$offline" in
    0|1) ;;
    *) echo "AILINUX_OFFLINE must be 0 or 1." >&2; exit 1 ;;
esac

if [ "$offline" = "1" ]; then
    command -v python3 >/dev/null 2>&1 || {
        echo "python3 is required to validate cached repository metadata." >&2
        exit 1
    }
    python3 - "$manifest_copy" "$include_root" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
include_root = pathlib.Path(sys.argv[2])
if not manifest_path.is_file():
    raise SystemExit(f"Missing cached repository manifest: {manifest_path}")

data = json.loads(manifest_path.read_text(encoding="utf-8"))
repos = data.get("repos")
if not isinstance(repos, list) or not repos:
    raise SystemExit("Cached third-party repository manifest is empty")

for repo in repos:
    source_file = include_root / repo["source_file"].lstrip("/")
    key_file = include_root / repo["key_dest"].lstrip("/")
    if not source_file.is_file():
        raise SystemExit(f"Missing cached repository source: {source_file}")
    expected = repo["source_content"].strip()
    actual = source_file.read_text(encoding="utf-8").strip()
    if actual != expected:
        raise SystemExit(f"Cached repository source differs from manifest: {source_file}")
    if not key_file.is_file() or key_file.stat().st_size == 0:
        raise SystemExit(f"Missing cached repository key: {key_file}")

print(f"Offline repository metadata validated: {len(repos)} repositories")
PY
    test -s "$source_dir/ailinux-mirror.list" || {
        echo "Cached AILinuX mirror source list is missing." >&2
        exit 1
    }
    echo "Using existing checked repository configuration without network refresh."
    exit 0
fi

for tool in bash curl python3 mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing repository sync dependency: $tool" >&2
        exit 1
    }
done

mkdir -p "$source_dir"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

installer="$tmp_dir/add-ailinux-repo.sh"
installer_lib="$tmp_dir/add-ailinux-repo.lib.sh"
manifest="$tmp_dir/third-party-repos.json"
specs="$tmp_dir/mirror-specs"
mirror_list="$source_dir/ailinux-mirror.list"

curl -fsSL --retry 3 --connect-timeout 15 \
    "$base_url/add-ailinux-repo.sh" -o "$installer"
curl -fsSL --retry 3 --connect-timeout 15 \
    "$base_url/shared_keys/third-party-repos.json" -o "$manifest"

# Load the canonical mirror specification function without executing main().
sed '/^main "\$@"$/d' "$installer" > "$installer_lib"
bash -eu -o pipefail -c '. "$1"; get_mirror_repo_specs "$2"' \
    sync-repositories "$installer_lib" "$codename" > "$specs"

{
    echo "# AILinuX mirror repositories"
    echo "# Generated from $base_url/add-ailinux-repo.sh"
    echo "# Codename: $codename"
} > "$mirror_list"

mirror_count=0
while IFS='|' read -r repo_path suites components archs probe_dist label signed_by key_url; do
    case "$repo_path" in
        ''|'#'*) continue ;;
    esac
    signed_by=${signed_by:-/usr/share/keyrings/ailinux-archive-keyring.gpg}
    if ! curl -fsSL --retry 2 --connect-timeout 10 \
        "$base_url/$repo_path/dists/$probe_dist/Release" -o /dev/null; then
        echo "Skipping unavailable mirror: $repo_path ($probe_dist)" >&2
        continue
    fi
    echo >> "$mirror_list"
    echo "# $label ($repo_path)" >> "$mirror_list"
    old_ifs=$IFS
    IFS=,
    for suite in $suites; do
        line="deb [arch=$archs signed-by=$signed_by] $base_url/$repo_path $suite"
        for component in $(printf '%s' "$components" | tr ',' ' '); do
            line="$line $component"
        done
        echo "$line" >> "$mirror_list"
    done
    IFS=$old_ifs
    mirror_count=$((mirror_count + 1))
done < "$specs"

python3 - "$manifest" "$include_root" "$base_url" "$manifest_copy" <<'PY'
import json
import pathlib
import sys
import urllib.request

manifest_path = pathlib.Path(sys.argv[1])
include_root = pathlib.Path(sys.argv[2])
base_url = sys.argv[3].rstrip("/")
manifest_copy = pathlib.Path(sys.argv[4])

data = json.loads(manifest_path.read_text(encoding="utf-8"))
repos = data.get("repos", [])
if not repos:
    raise SystemExit("Third-party repository manifest is empty")

for repo in repos:
    source_file = include_root / repo["source_file"].lstrip("/")
    key_file = include_root / repo["key_dest"].lstrip("/")
    source_file.parent.mkdir(parents=True, exist_ok=True)
    key_file.parent.mkdir(parents=True, exist_ok=True)

    source_file.write_text(repo["source_content"].rstrip() + "\n", encoding="utf-8")
    key_url = f"{base_url}/shared_keys/{repo['key']}"
    with urllib.request.urlopen(key_url, timeout=30) as response:
        key_data = response.read()
    if not key_data:
        raise SystemExit(f"Empty key download for {repo['id']}")
    key_file.write_bytes(key_data)
    key_file.chmod(0o644)

manifest_copy.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Third-party repositories synchronized: {len(repos)}")
PY

# Remove superseded handwritten names from earlier iterations.
rm -f \
    "$source_dir/ailinux-mirrors.list" \
    "$source_dir/third-party.list" \
    "$source_dir/mozilla.sources"

third_party_count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["repos"]))' "$manifest_copy")
test "$mirror_count" -gt 0
test "$third_party_count" -gt 0

echo "Mirror repositories synchronized: $mirror_count"
echo "Repository include tree ready: $source_dir"
