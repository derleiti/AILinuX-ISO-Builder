#!/usr/bin/env python3
"""Canonicalize live-build's generated GRUB live entries.

live-build emits an unversioned pair in addition to the per-kernel pair. The
unversioned entries hide which AILinuX kernel will actually boot and duplicate
the same commands. This helper keeps exactly one normal and one safe-mode
entry per kernel and gives both a stable AILinuX title.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MENUENTRY_RE = re.compile(
    r"^(?P<prefix>\s*menuentry\s+)(?P<quote>['\"])(?P<title>.*?)(?P=quote)(?P<suffix>.*\{.*)$"
)
DEBIAN_LIVE_RE = re.compile(
    r"^Debian GNU/Linux - live(?:, kernel (?P<version>.+?))?(?: \(fail-safe mode\))?$",
    re.IGNORECASE,
)
AILINUX_LIVE_RE = re.compile(
    r"^AILinuX (?P<version>.+?)(?: \(Safe Mode\))?$",
    re.IGNORECASE,
)
KERNEL_PATH_RE = re.compile(r"/casper/vmlinuz-(?P<version>[^\s'\"]+)")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+~-]*")


SEARCH_MARKER = "# AILINUX_SEARCH_ROOT"
SEARCH_BLOCK = (
    SEARCH_MARKER + "\n"
    "# Ventoy und aehnliche Loader starten ihr eigenes GRUB, in dem $root nicht\n"
    "# auf dieses Medium zeigt. Ohne diese Suche findet 'linux /casper/...' die\n"
    "# Datei nicht und GRUB meldet 'you need to load the kernel first'.\n"
    "# Schlaegt die Suche fehl, bleibt $root unveraendert - der direkte\n"
    "# Medienboot funktioniert dadurch unveraendert weiter.\n"
    "search --no-floppy --set=root --label AILINUX_2604\n"
    "if [ ! -e /.disk/info ]; then\n"
    "    search --no-floppy --set=root --file /.disk/info\n"
    "fi\n"
    "\n"
)


def ensure_search_root(text: str) -> str:
    """Make the medium locate itself before any menuentry runs."""

    if SEARCH_MARKER in text:
        return text
    match = re.search(r"^[ \t]*menuentry[ \t]", text, re.MULTILINE)
    if not match:
        raise ValueError("No menuentry found to anchor the root search")
    return text[: match.start()] + SEARCH_BLOCK + text[match.start() :]


@dataclass
class MenuBlock:
    text: str
    title: str


def brace_delta(line: str) -> int:
    """Count unquoted GRUB braces, ignoring comments."""

    delta = 0
    quote: str | None = None
    escaped = False
    for character in line:
        if escaped:
            escaped = False
            continue
        if character == "\\" and quote == '"':
            escaped = True
            continue
        if quote:
            if character == quote:
                quote = None
            continue
        if character in ("'", '"'):
            quote = character
        elif character == "#":
            break
        elif character == "{":
            delta += 1
        elif character == "}":
            delta -= 1
    return delta


def split_config(text: str) -> list[str | MenuBlock]:
    lines = text.splitlines(keepends=True)
    segments: list[str | MenuBlock] = []
    plain: list[str] = []
    index = 0

    while index < len(lines):
        match = MENUENTRY_RE.match(lines[index].rstrip("\r\n"))
        if not match:
            plain.append(lines[index])
            index += 1
            continue

        if plain:
            segments.append("".join(plain))
            plain = []

        block_lines = [lines[index]]
        depth = brace_delta(lines[index])
        index += 1
        while depth > 0 and index < len(lines):
            block_lines.append(lines[index])
            depth += brace_delta(lines[index])
            index += 1
        if depth != 0:
            raise ValueError(f"Unbalanced braces in menuentry {match.group('title')!r}")
        segments.append(MenuBlock("".join(block_lines), match.group("title")))

    if plain:
        segments.append("".join(plain))
    return segments


def live_entry(block: MenuBlock) -> tuple[str, bool, int] | None:
    debian_match = DEBIAN_LIVE_RE.fullmatch(block.title)
    ailinux_match = AILINUX_LIVE_RE.fullmatch(block.title)
    if not debian_match and not ailinux_match:
        return None

    safe_mode = "fail-safe mode" in block.title.lower() or block.title.lower().endswith(
        "(safe mode)"
    )
    title_version = (
        debian_match.group("version") if debian_match else ailinux_match.group("version")
    )
    path_match = KERNEL_PATH_RE.search(block.text)
    path_version = path_match.group("version") if path_match else None
    version = title_version or path_version

    if not version or not VERSION_RE.fullmatch(version):
        raise ValueError(f"Cannot determine a safe kernel version for {block.title!r}")
    if title_version and path_version and title_version != path_version:
        raise ValueError(
            f"Kernel title/path mismatch in {block.title!r}: {title_version!r} != {path_version!r}"
        )

    # Already canonical entries outrank live-build's explicit kernel entries;
    # explicit kernel entries outrank the duplicate generic entries.
    priority = 3 if ailinux_match else (2 if title_version else 1)
    return version, safe_mode, priority


def rewrite_title(block: MenuBlock, title: str) -> str:
    first_line, separator, rest = block.text.partition("\n")
    match = MENUENTRY_RE.match(first_line.rstrip("\r"))
    if not match:
        raise ValueError(f"Cannot rewrite malformed menuentry {block.title!r}")
    rewritten = first_line[: match.start("title")] + title + first_line[match.end("title") :]
    return rewritten + (separator + rest if separator else "")


def canonicalize(text: str) -> tuple[str, list[str]]:
    segments = split_config(text)
    candidates: dict[tuple[str, bool], tuple[int, int, MenuBlock]] = {}
    kernel_order: list[str] = []
    live_indexes: list[int] = []

    for index, segment in enumerate(segments):
        if not isinstance(segment, MenuBlock):
            continue
        details = live_entry(segment)
        if details is None:
            continue
        version, safe_mode, priority = details
        live_indexes.append(index)
        if version not in kernel_order:
            kernel_order.append(version)
        key = (version, safe_mode)
        previous = candidates.get(key)
        if previous is None or priority > previous[0]:
            candidates[key] = (priority, index, segment)

    if not live_indexes:
        raise ValueError("No live-build GRUB live entries were found")

    for version in kernel_order:
        missing = [
            label
            for safe_mode, label in ((False, "normal"), (True, "safe mode"))
            if (version, safe_mode) not in candidates
        ]
        if missing:
            raise ValueError(f"Kernel {version!r} is missing: {', '.join(missing)} entry")

    first_live_index = min(live_indexes)
    emitted: list[str] = []
    for version in kernel_order:
        for safe_mode in (False, True):
            block = candidates[(version, safe_mode)][2]
            title = f"AILinuX {version}" + (" (Safe Mode)" if safe_mode else "")
            emitted.append(rewrite_title(block, title))

    output: list[str] = []
    for index, segment in enumerate(segments):
        if index == first_live_index:
            output.extend(emitted)
        if index in live_indexes:
            continue
        output.append(segment.text if isinstance(segment, MenuBlock) else segment)

    result = ensure_search_root("".join(output))
    if "Debian GNU/Linux - live" in result:
        raise ValueError("A generic Debian live title remains after finalization")
    return result, kernel_order


def self_test() -> int:
    fixture = """set timeout=5
menuentry "Debian GNU/Linux - live" {
linux /casper/vmlinuz-7.2.0-test boot=casper
}
menuentry "Debian GNU/Linux - live (fail-safe mode)" {
linux /casper/vmlinuz-7.2.0-test boot=casper nomodeset
}
menuentry "Debian GNU/Linux - live, kernel 7.2.0-test" {
linux /casper/vmlinuz-7.2.0-test boot=casper
}
menuentry "Debian GNU/Linux - live, kernel 7.2.0-test (fail-safe mode)" {
linux /casper/vmlinuz-7.2.0-test boot=casper nomodeset
}
menuentry "Memory test" {
echo unchanged
}
"""
    finalized, versions = canonicalize(fixture)
    expected_titles = [
        'menuentry "AILinuX 7.2.0-test" {',
        'menuentry "AILinuX 7.2.0-test (Safe Mode)" {',
    ]
    actual_titles = [line for line in finalized.splitlines() if line.startswith("menuentry")]
    if versions != ["7.2.0-test"] or actual_titles != expected_titles + [
        'menuentry "Memory test" {'
    ]:
        raise AssertionError("GRUB finalizer produced unexpected menu entries")
    if canonicalize(finalized)[0] != finalized:
        raise AssertionError("GRUB finalizer is not idempotent")
    print("GRUB live-menu finalizer self-test passed")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if len(sys.argv) > 2:
        print(f"Usage: {Path(sys.argv[0]).name} [--self-test|GRUB_CFG]", file=sys.stderr)
        return 2

    grub_path = Path(sys.argv[1] if len(sys.argv) > 1 else "binary/boot/grub/grub.cfg")
    if not grub_path.is_file():
        print(f"Missing generated GRUB configuration: {grub_path}", file=sys.stderr)
        return 1

    original = grub_path.read_text(encoding="utf-8")
    try:
        finalized, versions = canonicalize(original)
    except ValueError as error:
        print(f"Cannot finalize {grub_path}: {error}", file=sys.stderr)
        return 1

    if finalized != original:
        mode = grub_path.stat().st_mode
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{grub_path.name}.", dir=grub_path.parent
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
                stream.write(finalized)
            os.chmod(temporary_name, mode)
            os.replace(temporary_name, grub_path)
        except BaseException:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass
            raise
        action = "Finalized"
    else:
        action = "Already finalized"

    print(f"{action} GRUB live menu for kernel(s): {', '.join(versions)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
