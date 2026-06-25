#!/bin/bash
# Outer build script: runs the Debian Sid container to build GParted Live arm64 ISO.
# Usage: ./build-arm64.sh [--use-cache]
#
# Supports:
#   macOS Apple Silicon  — Docker Desktop or OrbStack (runs as current user, no sudo)
#   Linux aarch64        — podman (runs via sudo for loop-mount access)
#
# Output: output/gparted-live-<date>-arm64.iso

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
mkdir -p "$OUTPUT_DIR"

USE_CACHE=""
if [ "$1" = "--use-cache" ]; then
  USE_CACHE="yes"
fi

echo "=== GParted Live arm64 Build ==="
echo "Script dir: $SCRIPT_DIR"
echo "Output dir: $OUTPUT_DIR"

# Cache directory for lb to reuse between builds
mkdir -p "$SCRIPT_DIR/lb-cache"

# Detect OS and pick the right container runner.
#
# macOS  — Docker Desktop (or OrbStack) runs arm64 containers natively on Apple Silicon.
#          No sudo needed; Docker Desktop's daemon handles privilege internally.
#          No :z volume label (that's a Linux SELinux annotation).
#
# Linux  — podman needs sudo so live-build can create loop mounts inside the container.
#          :z relabels the volume for SELinux (harmless if SELinux is permissive/disabled).
if [ "$(uname)" = "Darwin" ]; then
  if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker Desktop (or OrbStack) is required on macOS."
    echo "Install from https://www.docker.com/products/docker-desktop/ or https://orbstack.dev/"
    exit 1
  fi
  RUNNER="docker"
  VOL_OPTS=(-v "$SCRIPT_DIR:/build")
  SUDO=""
else
  if ! command -v podman &>/dev/null; then
    echo "ERROR: podman is required on Linux."
    exit 1
  fi
  RUNNER="podman"
  VOL_OPTS=(-v "$SCRIPT_DIR:/build:z")
  SUDO="sudo"
fi

CONTAINER_OPTS=(
  --rm
  --privileged
  "${VOL_OPTS[@]}"
  -e "USE_EXISTING_CACHE=${USE_CACHE}"
)

echo "Using runner: ${SUDO:+sudo }$RUNNER"
echo "Starting Debian Sid container..."
$SUDO $RUNNER run "${CONTAINER_OPTS[@]}" \
  docker.io/library/debian:sid \
  /bin/bash /build/build-arm64-inner.sh

echo ""
echo "=== Build complete ==="
echo "ISO output:"
ls -lh "$OUTPUT_DIR"/*.iso 2>/dev/null || echo "No ISO found in $OUTPUT_DIR"
