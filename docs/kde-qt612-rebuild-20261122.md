# KDE / Qt 6.12 compatibility rebuild, 2026-11-22

## Reason

On `zombie-pc`, `kscreenlocker_greet` and `ksmserver-logout-greeter`
repeatedly crashed in `libLayerShellQtInterface.so.6.8.2` at 0x108b1
following monitor power transitions and opening the logout/restart UI.
The November 12 login-loop incident also involved the Qt 6.12 / KWin
6.8.2 pair, with the crash entering KDE platform-theme code.

## Rebuilt binary packages (no workaround copied from zombie-pc)

- `liblayershellqtinterface6`, `layer-shell-qt`: KDE upstream v6.8.2,
  commit `842f397180f349380e9f7d466c9e746e4dd7faaa`.
- `plasma-integration`: KDE upstream v6.8.2,
  commit `b8233c2a238f97371014dc47a3f8ec8e10f41048`.
- Built with Qt 6.12.0 from AILinux KDE-neon mirror using CMake + Ninja.
- Package versions include `+ailinuxqt612.1`. Debs are in
  `config/packages.chroot/` and override the older mirror packages.
- `plasma-integration` retains the original distro package payload and
  replaces its built Qt 6 platform-theme plugin, preserving translations.

## Checks / limitations

- CMake builds succeeded, dynamic library references resolved (`ldd -r`).
- `layer-shell-qt`: upstream `ctest` 1/1 passed.
- `plasma-integration`: 2/9 headless tests passed, seven GUI tests require
  a suitable graphical desktop and cannot be considered runtime validated.
- `apt-get -s install` for all three local packages: no removals required.
- `scripts/test-kde-login-guard-regressions.sh`: all version gate scenarios pass.
- The gate only permits the formerly blocked Qt/KWin pair with *both*
  corrected component packages present; this is NOT proof that runtime works.
- The ISO MUST pass boot and installed-system verification plus actual KDE
  Wayland login, monitor off/on, screen lock/unlock, logout and shutdown tests
  before release. Do not propagate emergency `QT_QPA_PLATFORMTHEME=gnome`
  KWin wrapper from the old workstation into the ISO.
- The original Infinity login theme remains available as an optional theme
  payload, but clean installs use Breeze for SDDM and Breeze Dark for Plasma.

## SHA-256
69eed3bb65fb791b91040faf3e66f7c8c7b58383a4b0e922ea1073c1199c0604  config/packages.chroot/layer-shell-qt_6.8.2+p26.04+vstable+git20261027.1611-0+ailinuxqt612.1_amd64.deb
548f05b7a6e0dc27cb19701acd9adb29ffcf205387806288d0a5bd5c1401d2ee  config/packages.chroot/liblayershellqtinterface6_6.8.2+p26.04+vstable+git20261027.1611-0+ailinuxqt612.1_amd64.deb
4aa8118dd54c65c82e6393916b698c749d9b047f0c1c3d86fe4d40ee08e45b7a  config/packages.chroot/plasma-integration_6.8.2+p26.04+vstable+git20261028.0034-0+ailinuxqt612.1_amd64.deb
