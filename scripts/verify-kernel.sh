#!/usr/bin/env bash
# verify-kernel.sh — verify built Image, extract version string
set -e

: "${WORK_DIR:?}"

IMAGE="${WORK_DIR}/out/dist/Image"
[ -f "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE"; exit 1; }

VERSION_FULL=$(strings "$IMAGE" | grep "Linux version [0-9]" | head -1)
echo "$VERSION_FULL"

echo "$VERSION_FULL" | grep -q "dirty" && { echo "❌ Kernel is dirty!"; exit 1; } || true
echo "$VERSION_FULL" | grep -qE 'Linux version 5\.15\.' || {
  echo "[ERROR] Expected a real Linux 5.15 kernel version; refusing a spoofed or unexpected release." >&2
  exit 1
}

VERSION_CLEAN=$(echo "$VERSION_FULL" | sed 's/Linux version //' | sed 's/ (.*//')
echo "✅ $VERSION_CLEAN"
echo "KERNEL_VERSION=$VERSION_CLEAN" >> "${GITHUB_ENV:-/dev/null}"
echo "$VERSION_CLEAN" > "$WORK_DIR/out/dist/kernel_version.txt"
