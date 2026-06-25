# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This repository builds **GParted Live arm64** — an aarch64 port of the official GParted Live bootable ISO (https://gparted.org/livecd.php). The official ISO is amd64-only; this project produces an equivalent that boots via UEFI on arm64 hardware and VMs (VMware Fusion on Apple Silicon, UTM, etc.).

## Repository layout

```
/home/mz1/gparted/
├── clonezilla/          # upstream clone: stevenshiau/clonezilla (provides build scripts and hooks)
├── drbl/                # upstream clone: stevenshiau/drbl (provides drbl.conf with package lists)
├── output/              # ISO files written here after a successful build
├── lb-cache/            # optional lb package cache, speeds up re-runs
├── build-arm64.sh       # outer script: launches the Debian Sid container
└── build-arm64-inner.sh # inner script: runs inside the container, produces the ISO
```

## How the build works

GParted Live is built using Debian's `live-build` (`lb`) tool, which bootstraps a Debian Sid arm64 system, installs packages, runs customization hooks, and produces a bootable ISO. All of this happens inside a `debian:sid` container so the RHEL 10 host is unaffected.

**Two-stage architecture of the upstream `create-gparted-live` script:**
- Stage 1: `lb config` + `lb build` → raw template ISO (handled by `build-arm64-inner.sh`)
- Stage 2: repackage with custom syslinux/BIOS menus (x86-only → **skipped for arm64**)

`build-arm64-inner.sh` replaces Stage 1 only, using the GRUB EFI boot that `lb` generates natively for arm64.

**Key files from the `clonezilla` source that go into the ISO:**
- `clonezilla/setup/files/gparted/live-hook/gparted-live-hook` — chroot hook: configures auto-login, desktop, services, etc. inside the squashfs
- `clonezilla/setup/files/gparted/live-hook/gparted-efi-misc-binary-hook` — binary hook: normalises `vmlinuz`/`initrd` filenames (already arm64-aware)
- `clonezilla/setup/files/ocs/live-hook/ocs-live-hook-functions` — shell functions used by `gparted-live-hook`
- `clonezilla/setup/files/ocs/live-hook/ocs-live-hook.conf` — hook configuration (service lists, locale settings, etc.)

## Running the build

```bash
# First time: pull the Debian Sid container image (requires /etc/hosts workaround below)
sudo podman pull docker.io/library/debian:sid

# Run the build (~30-60 min first time, faster with --use-cache)
./build-arm64.sh

# Re-run using the preserved package cache
./build-arm64.sh --use-cache
```

Output: `output/gparted-live-YYYYMMDD-arm64.iso`

### Docker Hub DNS workaround (this host)

This RHEL host's DNS server doesn't let Go-based tools (like podman) resolve Docker Hub hostnames. Workaround: add the IPs to `/etc/hosts`:

```bash
# Resolve and add the required hosts
for host in registry-1.docker.io auth.docker.io production.cloudfront.docker.com; do
  ip=$(nslookup $host 172.16.189.2 2>/dev/null | grep "Address:" | grep -v "#" | head -1 | awk '{print $2}')
  echo "$ip $host" | sudo tee -a /etc/hosts
done
```

## arm64-specific changes vs upstream amd64 build

| Concern | amd64 | arm64 |
|---------|-------|-------|
| Bootloader | syslinux + grub-efi | grub-efi only (`--bootloaders grub-efi`) |
| Architecture flag | `--architectures amd64` | `--architectures arm64` |
| Linux kernel pkg | `linux-image-amd64` | `linux-image-arm64` (via `--linux-flavours arm64`) |
| `grub-pc` in packages | yes (BIOS GRUB for disk installs) | replaced with `grub-efi-arm64` |
| `v86d` | yes (VESA framebuffer helper) | removed (x86-only) |
| `libc6-i386` | yes (32-bit compat) | removed (x86-only) |
| ISO stage 2 | custom syslinux menus | skipped; lb GRUB EFI output used directly |

## Testing the ISO

Transfer `output/gparted-live-YYYYMMDD-arm64.iso` to a Mac with VMware Fusion on Apple Silicon:
- Create new VM → Other ARM → point to the ISO
- Firmware: UEFI (not BIOS)
- The ISO has only `EFI/BOOT/BOOTAA64.EFI` — no BIOS fallback

## Modifying the package list

Edit the heredoc in `build-arm64-inner.sh` (the `PKGLIST` block). Packages must exist in Debian Sid for arm64. After changes, run `./build-arm64.sh` (or `--use-cache` to reuse the bootstrap).

## Updating upstream sources

```bash
git -C clonezilla pull
git -C drbl pull
```

Then re-run the build. The inner script always reads hooks from the clonezilla source at build time.
