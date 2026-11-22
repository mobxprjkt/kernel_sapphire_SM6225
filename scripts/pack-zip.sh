#!/usr/bin/env bash
# Package the Image as a flashable AnyKernel3 ZIP.
set -euo pipefail
: "${WORK_DIR:?}"
IMAGE="${WORK_DIR}/out/dist/Image"
[ -f "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE" >&2; exit 1; }

AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
cd "$WORK_DIR"
rm -rf ak3_tmp
git clone --depth=1 "$AK3_REPO" ak3_tmp
cp "$IMAGE" ak3_tmp/Image

# Device-specific AnyKernel3 metadata for Xiaomi Redmi Note 13 4G (Sapphire).
cat > ak3_tmp/anykernel.sh <<'AK3'
### AnyKernel3 Ramdisk Mod Script
## Sapphire — SukiSU-Nova + SUSFS + KPM
properties() { '
kernel.string=Sapphire SukiSU-Nova + SUSFS + KPM
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=sapphire
device.name2=sapphiren
supported.versions=13-17
'; }

# Boot partition on A/B devices; AnyKernel3 resolves the active slot.
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# Replace the boot image kernel while preserving the existing ramdisk.
dump_boot;
write_boot;
AK3

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
