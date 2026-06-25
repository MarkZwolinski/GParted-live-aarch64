#!/bin/bash
# Inner build script: runs inside debian:sid container to produce GParted Live arm64 ISO.
# This script replicates Stage 1 of the upstream create-gparted-live for arm64.
# Stage 2 (syslinux/BIOS boot customization) is intentionally skipped; the lb-generated
# GRUB EFI boot is used directly, which is correct for UEFI-only arm64 platforms.
#
# Prerequisites placed by the outer script via bind mount at /build/:
#   /build/clonezilla/   - clone of stevenshiau/clonezilla
#   /build/drbl/         - clone of stevenshiau/drbl
#   /build/output/       - destination for the final ISO
#   /build/lb-cache/     - persistent lb cache directory (optional)

set -e

BUILD_ROOT="/build"
CLONEZILLA_SRC="$BUILD_ROOT/clonezilla"
OUTPUT_DIR="$BUILD_ROOT/output"
WORK_DIR="/tmp/lb-work"
CACHE_DIR="$BUILD_ROOT/lb-cache"

# Mirrors (override via environment if needed)
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR:-http://security.debian.org/debian-security}"

# DRBL package repository (provides drbl, clonezilla, and a patched live-boot)
DRBL_REPO_URL="${DRBL_REPO_URL:-http://free.nchc.org.tw/drbl-core}"
DRBL_GPG_KEY_URL="http://drbl.org/GPG-KEY-DRBL"

DEBIAN_DIST="sid"
DATE_TAG="$(date +%Y%m%d)"

echo "=== [inner] Installing build dependencies ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y --no-install-recommends \
  live-build \
  debootstrap \
  mmdebstrap \
  xorriso \
  binutils \
  xz-utils \
  cpio \
  bc \
  rsync \
  zip \
  wget \
  gnupg \
  ca-certificates \
  sudo \
  squashfs-tools

echo "=== [inner] Copying hook files from clonezilla source ==="
# These files get included inside the squashfs chroot's /live-hook-dir/
# and executed by the chroot hook during lb build.
OCS_LIVE_HOOK_SRC="$CLONEZILLA_SRC/setup/files/ocs/live-hook"
GPARTED_LIVE_HOOK_SRC="$CLONEZILLA_SRC/setup/files/gparted"

echo "=== [inner] Preparing build directory ==="
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Optionally restore lb cache from a previous run to avoid re-downloading packages
if [ -d "$CACHE_DIR/cache" ]; then
  echo "Restoring lb cache..."
  cp -a "$CACHE_DIR/cache" "$WORK_DIR/cache"
fi

cd "$WORK_DIR"

echo "=== [inner] Configuring live-build for arm64 ==="

export DEBOOTSTRAP_OPTIONS="--include=gnupg"

lb config \
  --distribution "$DEBIAN_DIST" \
  --parent-distribution "$DEBIAN_DIST" \
  --archive-areas "main contrib" \
  --architectures arm64 \
  --linux-packages "linux-image" \
  --linux-flavours arm64 \
  --binary-images iso-hybrid \
  --bootloaders grub-efi \
  --apt apt \
  --apt-options "--yes --no-upgrade --allow-downgrades" \
  --apt-recommends false \
  --firmware-binary false \
  --firmware-chroot false \
  --security false \
  --updates false \
  --initramfs live-boot \
  --bootappend-live "boot=live union=overlay config username=user" \
  --cache-indices true \
  --cache-packages false \
  --apt-indices false \
  --apt-source-archives true \
  --tasksel none \
  --memtest none \
  --debian-installer false \
  --win32-loader false \
  --zsync false \
  --checksums none \
  --source false \
  --initsystem systemd \
  --debootstrap-options "${DEBOOTSTRAP_OPTIONS} --variant=minbase" \
  --bootstrap mmdebstrap \
  --parent-mirror-bootstrap "$DEBIAN_MIRROR" \
  --parent-mirror-binary "$DEBIAN_MIRROR" \
  --parent-mirror-chroot "$DEBIAN_MIRROR" \
  --parent-mirror-chroot-security "$DEBIAN_SECURITY_MIRROR" \
  --parent-mirror-binary-security "$DEBIAN_SECURITY_MIRROR" \
  --mirror-bootstrap "$DEBIAN_MIRROR" \
  --mirror-chroot "$DEBIAN_MIRROR" \
  --mirror-chroot-security "$DEBIAN_SECURITY_MIRROR"

echo "=== [inner] Setting up package lists ==="
mkdir -p config/package-lists

# Packages for GParted Live arm64.
# Derived from the pkgs + debian_pkgs_for_gparted variables in create-gparted-live,
# with these arm64-specific changes:
#   grub-pc   -> grub-efi-arm64  (BIOS GRUB replaced by EFI GRUB for arm64 disk installs)
#   v86d         removed          (x86-only VESA framebuffer helper)
#   libc6-i386   not included     (x86 32-bit compatibility library only)
#   b3sum        added            (needed by gparted-live-hook initrd checksum hook)
cat > config/package-lists/gparted-packages.list.chroot << 'PKGLIST'
console-data
console-setup
console-common
kbd
file
eject
user-setup
grub-efi-arm64
fluxbox
idesk
man-db
testdisk
mc
less
lxterminal
zenity
x11-xserver-utils
feh
netpbm
nano
bogl-bterm
mdetect
lxrandr
sdparm
hdparm
discover
lsscsi
pciutils
ifupdown
isc-dhcp-client
cryptsetup
gpart
smartmontools
vim-tiny
gdisk
fsarchiver
mdadm
sudo
hicolor-icon-theme
netbase
ssh
pppoeconf
ethtool
whiptail
lshw
open-iscsi
tree
cifs-utils
nilfs-tools
netsurf-gtk
ca-certificates
scsitools
blktool
safecopy
net-tools
iproute2
iw
pcmanfm
geany
f2fs-tools
partclone
partimage
screen
rsync
iputils-ping
telnet
traceroute
bc
lsof
psmisc
dnsutils
wget
ftp
bzip2
xz-utils
zip
unzip
w3m
gsmartcontrol
gddrescue
zerofree
efibootmgr
libpam-systemd
polkitd
pkexec
galculator
yelp
init
udftools
haveged
f3
nwipe
hexedit
gvfs
pm-utils
b3sum
gparted
e2fsprogs
hfsutils
jfsutils
xfsprogs
xfsdump
reiserfsprogs
btrfs-progs
parted
ntfs-3g
dosfstools
mtools
lvm2
mbr
vim-common
dmsetup
kpartx
exfatprogs
util-linux-extra
xorg
xserver-xorg-legacy
fonts-arphic-uming
fonts-hanazono
PKGLIST

echo "=== [inner] Setting up chroot includes and hooks ==="
mkdir -p config/includes.chroot/live-hook-dir
mkdir -p config/hooks/live

# OCS live-hook functions and config (needed by gparted-live-hook at chroot time)
cp -pr "$OCS_LIVE_HOOK_SRC/." config/includes.chroot/live-hook-dir/

# GParted-specific hook scripts and desktop/config data
cp -pr "$GPARTED_LIVE_HOOK_SRC/live-hook/." config/includes.chroot/live-hook-dir/
# The gparted directory contains desktop icons, fluxbox menu, etc.
# gparted-live-hook copies these from /live-hook-dir/gparted/ at build time.
mkdir -p config/includes.chroot/live-hook-dir/gparted
cp -pr "$GPARTED_LIVE_HOOK_SRC/." config/includes.chroot/live-hook-dir/gparted/

# Minimal drbl-ocs.conf for the hook (provides service lists, locale config, etc.)
# The conf from the clonezilla source tree is the authoritative version.
cp "$CLONEZILLA_SRC/conf/drbl-ocs.conf" config/includes.chroot/live-hook-dir/

# drbl.conf provides debian_pkgs_for_gparted used by download_grub_1_2_deb_for_later_use
cp "$BUILD_ROOT/drbl/conf/drbl.conf" config/includes.chroot/live-hook-dir/

# Chroot hook: configures GParted Live environment inside the squashfs (runs at build time)
cp "$GPARTED_LIVE_HOOK_SRC/live-hook/gparted-live-hook" \
   config/hooks/live/gparted-live-hook.chroot
chmod 755 config/hooks/live/gparted-live-hook.chroot

# Binary hook: normalises vmlinuz/initrd filenames after squashfs creation
# Already handles the arm64 case (no syslinux hard links on arm64)
cp "$GPARTED_LIVE_HOOK_SRC/live-hook/gparted-efi-misc-binary-hook" \
   config/hooks/live/gparted-efi-misc-binary-hook.binary
chmod 755 config/hooks/live/gparted-efi-misc-binary-hook.binary

echo "=== [inner] Setting up DRBL APT repository ==="
mkdir -p config/archives

# Attempt to fetch DRBL GPG key; fall back gracefully if unreachable.
if wget -q --timeout=30 -O config/archives/drbl-gpg.key "$DRBL_GPG_KEY_URL"; then
  cat > config/archives/drbl-repository.list << DRBLREPO
deb $DRBL_REPO_URL drbl stable live-stable
deb-src $DRBL_REPO_URL drbl stable live-stable
DRBLREPO
  echo "DRBL repository configured."
else
  echo "WARNING: DRBL GPG key fetch failed — DRBL repository will not be added."
  echo "Build will use standard Debian Sid packages only."
  rm -f config/archives/drbl-gpg.key config/archives/drbl-repository.list
fi

echo "=== [inner] Running lb build ==="
lb build

echo "=== [inner] Collecting output ISO ==="
mkdir -p "$OUTPUT_DIR"

ISO_SRC="$(ls live-image-arm64*.iso 2>/dev/null | head -1)"
if [ -z "$ISO_SRC" ]; then
  echo "ERROR: No arm64 ISO found after lb build."
  ls -la
  exit 1
fi

ISO_DEST="$OUTPUT_DIR/gparted-live-${DATE_TAG}-arm64.iso"
mv "$ISO_SRC" "$ISO_DEST"
echo "ISO created: $ISO_DEST ($(du -sh "$ISO_DEST" | cut -f1))"

echo "=== [inner] Saving lb cache ==="
if [ -d "$WORK_DIR/cache" ]; then
  rm -rf "$CACHE_DIR/cache"
  cp -a "$WORK_DIR/cache" "$CACHE_DIR/cache"
fi

echo "=== [inner] Done ==="
