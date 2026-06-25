#!/bin/bash
# Outer build script: runs the Debian Sid container to build GParted Live arm64 ISO.
# Usage: ./build-arm64.sh [--use-cache]
#
# Supports:
#   macOS Apple Silicon       — Docker Desktop or OrbStack (no sudo, no SELinux :z)
#   Linux with Docker Engine  — Ubuntu and other non-SELinux distros (no sudo if user
#                               is in the docker group; no :z volume label)
#   Linux with podman         — RHEL/Fedora (sudo podman; :z for SELinux relabeling)
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
# macOS / Linux+Docker  — Docker daemon handles privilege internally; no sudo needed
#                         (on Linux, user must be in the docker group).
#                         No :z volume label — that's an SELinux-only annotation.
#
# Linux+podman          — sudo required so live-build can create loop mounts.
#                         :z relabels the volume for SELinux (RHEL/Fedora).
if [ "$(uname)" = "Darwin" ]; then
  if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker Desktop (or OrbStack) is required on macOS."
    echo "Install from https://www.docker.com/products/docker-desktop/ or https://orbstack.dev/"
    exit 1
  fi
  RUNNER="docker"
  VOL_OPTS=(-v "$SCRIPT_DIR:/build")
  SUDO=""
elif command -v docker &>/dev/null; then
  # Linux with Docker Engine (Ubuntu, Debian, etc.)
  # Runs without sudo if the current user is in the docker group.
  RUNNER="docker"
  VOL_OPTS=(-v "$SCRIPT_DIR:/build")
  SUDO=""
else
  # Linux with podman (RHEL, Fedora)
  if ! command -v podman &>/dev/null; then
    echo "ERROR: docker or podman is required on Linux."
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
