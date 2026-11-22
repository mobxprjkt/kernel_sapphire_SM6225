#!/usr/bin/env bash
# Package the Image as a flashable AnyKernel3 ZIP.
set -euo pipefail
: "${WORK_DIR:?}"
IMAGE="${WORK_DIR}/out/dist/Image"
[ -f "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE" >&2; exit 1; }

AK3_REPO="https://github.com/superuseryu/AnyKernel3"
cd "$WORK_DIR"
rm -rf ak3_tmp
git clone --depth=1 "$AK3_REPO" ak3_tmp
cp "$IMAGE" ak3_tmp/Image

VERSION_FILE="${WORK_DIR}/out/dist/kernel_version.txt"
RAW_VERSION=$([ -f "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" || echo "5.15.x")
KERNEL_VERSION=$(echo "$RAW_VERSION" | grep -oP '^\d+\.\d+\.\d+' || echo "$RAW_VERSION")
ZIP_NAME="AK3-Sapphire-SukiSU-Nova-SUSFS-KPM-${KERNEL_VERSION}-$(date +'%Y-%m').zip"

cd ak3_tmp
zip -r9 "../${ZIP_NAME}" * -x .git/*
cd ..
rm -rf ak3_tmp

echo "ZIP_NAME=$ZIP_NAME" >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] Created $ZIP_NAME"
