# AILinux 26.05 clean ISO — build and QA record, 2026-11-22

## Defect and remediation

- The first fresh ISO booted into SDDM but had no working system D-Bus or
  `systemd-logind`; `dbus-daemon` failed with `Permission denied`.
- Root cause: restrictive Git checkout `umask 0027` made 592 public include
  directories mode `0750` and over 79,000 public theme/config files mode
  `0640`. `live-build` copied those modes into `/usr`, `/usr/lib`, `/etc` and
  graphical assets. The early graphical-ready marker did not test real login.
- `scripts/normalize-iso-include-perms.sh` corrects public include tree mode
  and preserves intentionally private files (`0600`). It runs before both
  `create.sh` and direct rootless/live-build paths.
- `config/hooks/0197-verify-runtime-access.chroot` checks final live runtime
  permissions and corrects the top-level chroot root directory to `0755`.
- `scripts/validate-live-rootfs-permissions.sh` checks the **compressed,
  final SquashFS** for critical access paths. Integrated in `build.sh`.
- KDE uses Breeze/Breeze Dark by default. Three KDE Neon upstream 6.8.2
  components are locally rebuilt for Qt 6.12 and included as `.deb` files:
  `layer-shell-qt`, `liblayershellqtinterface6`, `plasma-integration`.
  A package pair gate rejects the earlier known-bad versions.

## Artifact

- AILinux 26.05, Resolute base, `ailinux-kernel-ai-gaming` 7.3.5.
- `ailinux-26.05-amd64-20261122T100914Z.iso`
- ISO size: 5,298,630,656 bytes.
- SHA-256: `4acdea23e51be4a5c7a6ffcb9ac1388a3501ed7580c3a8781d08f78bff48df8b`.
- Fresh online bootstrap and full package download from AILinux mirrors;
  not an in-place upgrade or reuse of the previous live filesystem.

## Verified

- Project static validation and package gate regression tests: PASS.
- Actual SquashFS metadata: `/`, `/usr`, `/usr/lib`, `/usr/lib/systemd`,
  `/usr/share`, `/etc`, `/usr/share/plasma`, `/usr/share/sddm` are world
  traversable (`0755`). Public desktop config files mode `0644`.
- Structural ISO check: BIOS, UEFI, hybrid-USB, Ventoy discovery: PASS.
- ISO SHA-256: PASS.
- Automated QEMU BIOS/CD-ROM, BIOS/USB, UEFI/CD-ROM, UEFI/USB: 4/4 PASS.
- Separate live QEMU guest-agent Wayland test: SDDM, system D-Bus,
  systemd-logind active, `kwin_wayland` running, user seat session present:
  PASS. `loginctl lock-session` and `unlock-session`: PASS. No kernel
  `kscreenlocker`/`kwin_wayland` segfaults.
- KDE `org.kde.LogoutPrompt.promptReboot` D-Bus method invocation: PASS;
  greeter process observed alive during VM test (at least two seconds), no
  observed kernel segfault/core dump. No actual reboot was initiated.
- Remote transfer to another machine: SHA-256 matched the original server ISO.

## Not yet verified / release caveat

- Physical AMD Wayland multi-monitor power-off/on and actual shutdown UI.
- A full Calamares install into a disposable target and installed-system
  boot/upgrade-path test. Booting the live ISO is NOT a full install test.
- Hardware ISO boot and physical installer test remain required before
  repartitioning a production workstation.
- The test ISO should not be published as a general release solely on this
  QEMU coverage; no public release was performed during these checks.
