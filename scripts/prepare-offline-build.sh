#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state_dir="$project_dir/.offline-build-state"
packages_dir="$project_dir/config/packages.chroot"
checksums_file="$project_dir/config/offline-packages.sha256"
archive_file="$project_dir/config/archives/ailinux-mirrors.list.chroot"
archive_backup="$state_dir/ailinux-mirrors.list.chroot"
staged_manifest="$state_dir/staged-packages.tsv"

die() {
    echo "Offline build preparation failed: $*" >&2
    exit 1
}

require_tools() {
    for tool in awk chmod cp dpkg dpkg-deb grep mkdir mv rm rmdir sed sha256sum; do
        command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
    done
}

expected_checksum() {
    package_name=$1
    awk -v package_name="$package_name" '
        $2 == package_name {
            if (found) exit 2
            print $1
            found = 1
        }
        END { if (!found) exit 1 }
    ' "$checksums_file"
}

verify_candidate() {
    candidate=$1
    candidate_basename=${candidate##*/}

    case "$candidate_basename" in
        ''|*/*|*[!A-Za-z0-9.+_:%~-]*) return 1 ;;
        *.deb) ;;
        *) return 1 ;;
    esac

    candidate_expected=$(expected_checksum "$candidate_basename" 2>/dev/null) || return 1
    printf '%s\n' "$candidate_expected" | grep -Eq '^[0-9a-f]{64}$' || return 1

    dpkg-deb --info "$candidate" >/dev/null 2>&1 || return 1
    candidate_package=$(dpkg-deb -f "$candidate" Package)
    candidate_version=$(dpkg-deb -f "$candidate" Version)
    candidate_arch=$(dpkg-deb -f "$candidate" Architecture)
    case "$candidate_arch" in
        amd64|all) ;;
        *) return 1 ;;
    esac
    case "$candidate_basename" in
        *_"$candidate_arch".deb) ;;
        *) return 1 ;;
    esac

    candidate_checksum=$(sha256sum "$candidate" | awk '{ print $1 }')
    [ "$candidate_checksum" = "$candidate_expected" ] || {
        echo "Ignoring cached package with a checksum mismatch: $candidate" >&2
        return 1
    }
    return 0
}

cache_directories() {
    if [ -n "${AILINUX_OFFLINE_PACKAGE_CACHE:-}" ]; then
        printf '%s\n' "$AILINUX_OFFLINE_PACKAGE_CACHE"
    fi
    printf '%s\n' \
        "$project_dir/cache/packages.chroot" \
        "$project_dir/cache/packages_chroot" \
        "$project_dir/cache/packages.binary" \
        "$project_dir/cache/packages_binary"
}

select_packages() {
    # shellcheck disable=SC1090
    . "$project_dir/config/ailinux-kernel.env"
    expected_kernel_package=${AILINUX_KERNEL_PACKAGE:?}
    expected_kernel_version=${AILINUX_KERNEL_VERSION:?}

    selected_kernel=
    selected_kernel_checksum=
    selected_copa=
    selected_copa_version=
    selected_copa_checksum=

    cache_directories | while IFS= read -r cache_dir; do
        [ -d "$cache_dir" ] || continue
        for candidate in "$cache_dir"/*.deb; do
            [ -f "$candidate" ] || continue
            verify_candidate "$candidate" || continue

            case "$candidate_package" in
                "$expected_kernel_package")
                    [ "$candidate_version" = "$expected_kernel_version" ] || continue
                    if [ -s "$state_dir/selected-kernel" ]; then
                        old_checksum=$(sed -n '2p' "$state_dir/selected-kernel")
                        [ "$old_checksum" = "$candidate_checksum" ] || \
                            die "ambiguous cached kernel packages for $candidate_package $candidate_version"
                    else
                        printf '%s\n%s\n' "$candidate" "$candidate_checksum" > "$state_dir/selected-kernel"
                    fi
                    ;;
                copa)
                    if [ ! -s "$state_dir/selected-copa" ]; then
                        printf '%s\n%s\n%s\n' "$candidate" "$candidate_checksum" "$candidate_version" > "$state_dir/selected-copa"
                    else
                        old_version=$(sed -n '3p' "$state_dir/selected-copa")
                        old_checksum=$(sed -n '2p' "$state_dir/selected-copa")
                        if dpkg --compare-versions "$candidate_version" gt "$old_version"; then
                            printf '%s\n%s\n%s\n' "$candidate" "$candidate_checksum" "$candidate_version" > "$state_dir/selected-copa"
                        elif dpkg --compare-versions "$candidate_version" eq "$old_version"; then
                            [ "$old_checksum" = "$candidate_checksum" ] || \
                                die "ambiguous cached Copa packages for version $candidate_version"
                        fi
                    fi
                    ;;
            esac
        done
    done

    [ -s "$state_dir/selected-kernel" ] || \
        die "trusted cache entry not found for $expected_kernel_package $expected_kernel_version"
    [ -s "$state_dir/selected-copa" ] || \
        die "trusted Copa package not found in the local live-build cache"
}

stage_one() {
    source_file=$1
    expected=$2
    target_name=${source_file##*/}
    target="$packages_dir/$target_name"

    if [ -e "$target" ]; then
        existing=$(sha256sum "$target" | awk '{ print $1 }')
        [ "$existing" = "$expected" ] || die "refusing to overwrite existing $target"
        echo "Using existing offline package: $target_name"
        return 0
    fi

    temporary="$state_dir/$target_name.tmp"
    cp "$source_file" "$temporary"
    copied=$(sha256sum "$temporary" | awk '{ print $1 }')
    [ "$copied" = "$expected" ] || die "copy verification failed for $target_name"
    printf '%s\t%s\t%s\n' "$target_name" "$expected" "$source_file" >> "$staged_manifest"
    mv "$temporary" "$target"
    chmod 0644 "$target"
    echo "Staged trusted offline package: $target_name"
}

stage() {
    require_tools
    [ -s "$checksums_file" ] || die "missing checksum allow-list: $checksums_file"
    [ -s "$project_dir/config/ailinux-kernel.env" ] || die "missing kernel selection"
    [ ! -e "$state_dir" ] || die "stale state exists; run '$0 cleanup' first"

    mkdir -m 0700 "$state_dir"
    mkdir -p "$packages_dir"
    : > "$staged_manifest"
    select_packages

    kernel_file=$(sed -n '1p' "$state_dir/selected-kernel")
    kernel_checksum=$(sed -n '2p' "$state_dir/selected-kernel")
    copa_file=$(sed -n '1p' "$state_dir/selected-copa")
    copa_checksum=$(sed -n '2p' "$state_dir/selected-copa")
    stage_one "$kernel_file" "$kernel_checksum"
    stage_one "$copa_file" "$copa_checksum"
    echo "Offline package staging complete."
}

mask_archive() {
    [ -d "$state_dir" ] || die "offline state is not prepared"
    if [ -e "$archive_backup" ]; then
        [ ! -e "$archive_file" ] || die "archive and backup both exist"
        return 0
    fi
    [ -f "$archive_file" ] || die "missing AILinuX archive file: $archive_file"
    mv "$archive_file" "$archive_backup"
    echo "Disabled repo.ailinux.me archive for this build."
}

cleanup() {
    require_tools
    [ -e "$state_dir" ] || return 0
    cleanup_failed=0

    if [ -f "$staged_manifest" ]; then
        tab=$(printf '\t')
        while IFS="$tab" read -r target_name expected source_file; do
            [ -n "$target_name" ] || continue
            case "$target_name" in
                ''|*/*|*[!A-Za-z0-9.+_:%~-]*)
                    echo "Unsafe staged package name retained: $target_name" >&2
                    cleanup_failed=1
                    continue
                    ;;
                *.deb) ;;
                *)
                    echo "Invalid staged package name retained: $target_name" >&2
                    cleanup_failed=1
                    continue
                    ;;
            esac
            target="$packages_dir/$target_name"
            [ -e "$target" ] || continue
            current=$(sha256sum "$target" | awk '{ print $1 }')
            if [ "$current" = "$expected" ]; then
                # `lb clean --purge` removes live-build's cache. Preserve the
                # two allow-listed AILinuX packages for the next offline run.
                case "$source_file" in
                    "$project_dir"/cache/*)
                        if [ ! -e "$source_file" ]; then
                            mkdir -p "${source_file%/*}"
                            cp "$target" "$source_file"
                            chmod 0644 "$source_file"
                        else
                            source_checksum=$(sha256sum "$source_file" | awk '{ print $1 }')
                            if [ "$source_checksum" != "$expected" ]; then
                                echo "Cached source changed and was not overwritten: $source_file" >&2
                                cleanup_failed=1
                            fi
                        fi
                        ;;
                esac
                rm -f "$target"
            else
                echo "Modified staged package retained for inspection: $target" >&2
                cleanup_failed=1
            fi
        done < "$staged_manifest"
    fi

    if [ -e "$archive_backup" ]; then
        if [ -e "$archive_file" ]; then
            echo "Cannot restore archive; target already exists: $archive_file" >&2
            cleanup_failed=1
        else
            mv "$archive_backup" "$archive_file"
        fi
    fi

    if [ "$cleanup_failed" -eq 0 ]; then
        rm -f \
            "$state_dir/selected-kernel" \
            "$state_dir/selected-copa" \
            "$state_dir"/*.tmp \
            "$staged_manifest"
        rmdir "$state_dir"
        echo "Offline build staging cleaned up."
    fi
    return "$cleanup_failed"
}

case "${1:-}" in
    stage) stage ;;
    mask-archive) mask_archive ;;
    cleanup) cleanup ;;
    *)
        echo "Usage: $0 {stage|mask-archive|cleanup}" >&2
        exit 2
        ;;
esac
