# AILinux APT repository regression — 22 November 2026

## Observed after fresh AILinux 26.05 installation on zombie-pc

- /etc/apt/sources.list contained three duplicated binary AILinux Ubuntu
  mirror entries alongside the canonical ailinux-mirror.list. It also
  requested deb-src indices that the binary mirror does not publish.
- /var/lib/apt/lists, /var/cache/apt, and /var/cache/apt/archives had
  mode 0750, owned by root:root. The unprivileged _apt downloader could
  not traverse the parent directories and APT fell back to root for fetches.
- The direct Antigravity APT entry did not restrict arch=amd64, causing an
  i386 index warning on a Steam multiarch installation.
- Upstream direct vendor sources coexist with signed AILinux mirrors.
  We did not blindly delete those separate URLs or their vendor credentials.

## Remediation for the next ISO and Calamares target

- config/includes.chroot/usr/local/sbin/ailinux-apt-source-sanity
  checks canonical signed Ubuntu mirrors before disabling any duplicates.
  It comments only identical mirrored Ubuntu entries in /etc/apt/sources.list,
  including unsupported deb-src, while retaining unrelated user repositories.
- Repairs traversal on APT parent directories to 0755 and keeps _apt
  partial directories private (0700, owner _apt).
- Constrains the direct Antigravity source to amd64 when needed.
- Hook 0050 prepares APT directory traversal before package operations;
  0190 runs the repair before the final upgrade, 0197 re-runs and checks
  it before filesystem compression. The installed-target Calamares cleanup
  re-runs the repair after all package and network modules.
- scripts/validate-live-rootfs-permissions.sh now refuses SquashFS files
  with broken APT directory modes. scripts/verify-installed-system.sh
  checks those invariants read-only on an installed target.
- scripts/test-apt-source-sanity.sh tests duplicate handling, alternate
  custom sources, i386 restriction, idempotence, 0750 regression, and
  refusal to modify when canonical mirror coverage is incomplete.

## Verification

- On the running zombie-pc, the original APT files and directory modes
  were backed up under /var/backups/ailinux-apt-repair-20261122/.
- Corrected the six duplicate/unsupported Ubuntu sources and APT directory
  modes; a real LC_ALL=C apt-get update passed with exit 0 and zero warnings.
- Deployed the same helper to /usr/local/sbin/ailinux-apt-source-sanity on
  zombie-pc; re-ran it and repeated apt-get update with zero warnings.
- Project validation and APT regression tests passed on the server.
- The older 26.05 ISO's compressed rootfs FAILS the extended test on
  exactly the broken /var/cache/apt, /var/cache/apt/archives, partial
  archive and /var/lib/apt/lists modes — this is the intended regression.
- This change is for the NEXT ISO build. A rebuilt SquashFS/ISO and
  a new Calamares install test are needed before calling the new image
  validated. The existing published ISO was NOT overwritten.

## Rollback

On zombie-pc, recover the original APT files and modes from
/var/backups/ailinux-apt-repair-20261122/ if required. In source, revert
the commit that introduced the helper, hooks and extended checks.
