#!/usr/bin/env bash
# verify-kernel.sh — verify built Image, extract version string
set -e

: "${WORK_DIR:?}"

IMAGE="${WORK_DIR}/out/dist/Image"
CONFIG="${WORK_DIR}/out/dist/.config"
[ -s "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE"; exit 1; }
[ -s "$CONFIG" ] || { echo "[ERROR] Final kernel .config not found"; exit 1; }
for symbol in CONFIG_KPM CONFIG_KALLSYMS CONFIG_KALLSYMS_ALL CONFIG_KSU CONFIG_KSU_SUSFS; do
  grep -qx "$symbol=y" "$CONFIG" || {
    echo "[ERROR] Final image config missing $symbol=y" >&2
    exit 1
  }
done
[ -s "${WORK_DIR}/kpm-build-proof.txt" ] || {
  echo "[ERROR] KPM build proof missing" >&2
  exit 1
}
echo "[OK] KPM + kallsyms final config verified"

# Require the actual KernelPatch runtime in Image, not just CONFIG_KPM=y.
bash "$WORK_DIR/scripts/patch-kpm-image.sh" verify \
  "$IMAGE" "$WORK_DIR/kpm-image-proof.txt"

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
