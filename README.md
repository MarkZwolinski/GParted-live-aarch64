# GParted Live arm64

> ## ⚠ EXPERIMENTAL SOFTWARE — USE AT YOUR OWN RISK
>
> This is an **unofficial, experimental** aarch64 port of GParted Live. It is **not** affiliated with, endorsed by, or supported by the GParted project or the Debian project.
>
> **Neither the repository owner nor Claude (Anthropic) accept any liability for data loss, disk corruption, or any other damage arising from the use of this software.**
>
> This build has been compiled and tested on macOS only (MacBook Pro M4, VMware Fusion). Behaviour on other platforms is untested.
>
> **You are very strongly advised to make a full backup of any virtual disk before attaching it to a VM running this ISO. Partition management tools can cause irreversible data loss if used incorrectly or if they malfunction.**
>
> By using this software you accept these risks entirely.

An aarch64 port of [GParted Live](https://gparted.org/livecd.php) — the bootable disk partition management ISO. The official release is amd64-only; this project builds an equivalent ISO that boots on arm64 hardware and VMs.

**Target:** VMware Fusion on Apple Silicon (M1/M2/M3 Mac), UTM, or any UEFI arm64 VM host.

## Requirements

### macOS Apple Silicon

Install **one** of:
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [OrbStack](https://orbstack.dev/) (lighter alternative)

`git` and `bash` are already present on macOS. If `git` is missing, run `xcode-select --install`.

### Linux aarch64 — Ubuntu / Debian

Install Docker Engine and add your user to the `docker` group:

```bash
sudo apt-get install docker.io
sudo usermod -aG docker $USER
newgrp docker   # or log out and back in
```

### Linux aarch64 — RHEL / Fedora

- `podman` — the build runs via `sudo podman` so live-build can create loop mounts inside the container

All platforms pull `debian:sid` from Docker Hub and run it as a native arm64 container. All other build tools (`live-build`, `debootstrap`, etc.) are installed automatically inside the container.

## Quick start

```bash
# 1. Copy or clone these scripts onto your machine, then enter the directory
#    (if you're cloning this repo: git clone <this-repo> && cd gparted)

# 2. Clone the upstream build dependencies into the same directory
git clone --depth=1 https://github.com/stevenshiau/clonezilla
git clone --depth=1 https://github.com/stevenshiau/drbl

# 3. Pull the Debian Sid container image (one-time)
#    macOS:
docker pull docker.io/library/debian:sid
#    Linux:
sudo podman pull docker.io/library/debian:sid

# 4. Build
./build-arm64.sh
```

Output: `output/gparted-live-YYYYMMDD-arm64.iso` (~700 MB, ~30–60 min first run)

Subsequent builds reuse the package cache:

```bash
./build-arm64.sh --use-cache
```

## DNS workaround (RHEL/Fedora only — if podman can't reach Docker Hub)

On some RHEL hosts, Go-based tools (including podman) fail to resolve Docker Hub hostnames even when the network is otherwise reachable. This does not affect macOS or Ubuntu (Docker Engine uses its own DNS resolver). Fix by adding the IPs to `/etc/hosts`:

```bash
for host in registry-1.docker.io auth.docker.io production.cloudfront.docker.com; do
  ip=$(nslookup $host 2>/dev/null | grep "Address:" | grep -v "#" | head -1 | awk '{print $2}')
  echo "$ip $host" | sudo tee -a /etc/hosts
done
```

## Testing the ISO

1. Copy `output/gparted-live-YYYYMMDD-arm64.iso` to a Mac with VMware Fusion
2. Create a new VM: **Other ARM 64-bit**
3. Point the CD/DVD drive at the ISO
4. Ensure firmware is **UEFI** (not BIOS)
5. Boot — the GRUB menu appears, then GParted launches automatically

## VMware Fusion recommended settings

After creating the VM but **before booting it**, open **VM → Settings** and apply the changes below. VMware Fusion may start the VM automatically at the end of the creation wizard — if it does, shut it down before making these changes.

### Memory — required

| Setting | Value | Why |
|---------|-------|-----|
| Memory | **2048 MB** (minimum) | The ISO boots with `toram`, which copies the squashfs (~500–700 MB) into RAM before mounting it. 768 MB (the Fusion default) leaves the running system with almost no free memory. |

### Settings that reduce host footprint

These can be changed in **VM → Settings** or by editing the `.vmx` file directly (the VM must be shut down first):

| Setting | VMX key | Recommended value | Why |
|---------|---------|-------------------|-----|
| Sound | `sound.present` | `FALSE` | GParted has no audio; the virtual sound device wastes resources |
| Video memory | `svga.vramSize` | `16777216` (16 MB) | The default 256 MB is far more than a 2D fluxbox desktop needs; frees ~240 MB of host RAM |
| VMware Tools time sync | `tools.syncTime` | `FALSE` | VMware Tools is not installed in GParted Live; the sync attempts achieve nothing |
| VMware Tools upgrade | `tools.upgrade.policy` | `manual` | Same reason |

To edit the `.vmx` directly, locate it at `~/Virtual Machines/<name>.vmwarevm/<name>.vmx`, make the changes in a text editor, then open the VM in Fusion.

## How it works

GParted Live is built with Debian's `live-build` tool, which bootstraps a Debian Sid arm64 system, installs packages, runs customization hooks, and produces a bootable ISO. The build runs entirely inside a `debian:sid` container.

The upstream build process has two stages:
1. `lb build` → raw Debian Live ISO (ported to arm64 here)
2. Repackage with custom syslinux/BIOS boot menus (x86-only — **skipped**)

For arm64, live-build's native GRUB EFI output is used directly. The ISO boots UEFI-only; there is no BIOS/CSM fallback.

## arm64 changes vs the official amd64 build

| | amd64 (official) | arm64 (this build) |
|---|---|---|
| Bootloader | syslinux + grub-efi | grub-efi only |
| GRUB binary | `BOOTX64.EFI` | `BOOTAA64.EFI` |
| In-system GRUB pkg | `grub-pc` | `grub-efi-arm64` |
| `v86d` | included | removed (x86 VESA only) |
| `libc6-i386` | included | removed (x86 32-bit compat) |
| `memtest86+` | included | not included (x86 only) |

All disk management tools (GParted, TestDisk, parted, e2fsprogs, btrfs-progs, etc.) are the same.

## Customising the package list

Edit the `PKGLIST` heredoc in `build-arm64-inner.sh`. All packages must exist in Debian Sid for arm64. Run `./build-arm64.sh --use-cache` after changes.

## Updating upstream sources

```bash
git -C clonezilla pull
git -C drbl pull
./build-arm64.sh
```

## Repository layout

```
clonezilla/          upstream clone (provides hooks and build scripts)
drbl/                upstream clone (provides drbl.conf with package lists)
output/              ISO files written here after a successful build
lb-cache/            live-build package cache (auto-populated, speeds up re-runs)
build-arm64.sh       outer script — launches the Debian Sid container
build-arm64-inner.sh inner script — runs lb config + lb build inside the container
```
