#!/usr/bin/env bash
# Package the built Image using the user's supplied AnyKernel3 archive.
set -euo pipefail
: "${WORK_DIR:?}"
IMAGE="${WORK_DIR}/out/dist/Image"
AK3_SOURCE="${WORK_DIR}/AnyKernel3"
[ -s "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE" >&2; exit 1; }
[ -s "$AK3_SOURCE/anykernel.sh" ] || { echo "[ERROR] Supplied AnyKernel3/anykernel.sh missing" >&2; exit 1; }
[ -s "$AK3_SOURCE/tools/ak3-core.sh" ] || { echo "[ERROR] Supplied AnyKernel3/tools/ak3-core.sh missing" >&2; exit 1; }
bash "$WORK_DIR/scripts/patch-kpm-image.sh" verify \
  "$IMAGE" "$WORK_DIR/kpm-image-proof.txt"

cd "$WORK_DIR"
rm -rf ak3_tmp
mkdir -p ak3_tmp
cp -a "$AK3_SOURCE/." ak3_tmp/
cp "$IMAGE" ak3_tmp/Image

# Keep the user's AnyKernel3 installer unchanged. Only add the freshly built Image.
grep -q '^do.devicecheck=0$' ak3_tmp/anykernel.sh || \
  echo "[INFO] AnyKernel device check setting differs from supplied archive; preserving it."
grep -q '^do.modules=0$' ak3_tmp/anykernel.sh || \
  echo "[INFO] AnyKernel module setting differs from supplied archive; preserving it."
grep -q '^do.systemless=1$' ak3_tmp/anykernel.sh || \
  echo "[INFO] AnyKernel systemless setting differs from supplied archive; preserving it."

VERSION_FILE="${WORK_DIR}/out/dist/kernel_version.txt"
RAW_VERSION=$([ -s "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" || echo "5.15.x")
KERNEL_VERSION=$(echo "$RAW_VERSION" | grep -oP '^\d+\.\d+\.\d+' || echo "$RAW_VERSION")
ZIP_NAME="AK3-Sapphire-SukiSU-Nova-SUSFS-KPM-${KERNEL_VERSION}-$(date +'%Y-%m').zip"

cd ak3_tmp
zip -r9 "../${ZIP_NAME}" . -x './.git/*' './.git'
cd ..
rm -rf ak3_tmp

echo "ZIP_NAME=$ZIP_NAME" >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] Created $ZIP_NAME using supplied AnyKernel3 archive"
