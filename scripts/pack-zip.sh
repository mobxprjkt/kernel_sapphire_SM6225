#!/usr/bin/env bash
# Package the Image as a flashable AnyKernel3 ZIP.
set -euo pipefail
: "${WORK_DIR:?}"
IMAGE="${WORK_DIR}/out/dist/Image"
[ -f "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE" >&2; exit 1; }
bash "$WORK_DIR/scripts/patch-kpm-image.sh" verify \
  "$IMAGE" "$WORK_DIR/kpm-image-proof.txt"

AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
cd "$WORK_DIR"
rm -rf ak3_tmp
git clone --depth=1 "$AK3_REPO" ak3_tmp
cp "$IMAGE" ak3_tmp/Image

# Device-specific AnyKernel3 metadata for Xiaomi Redmi Note 13 4G (Sapphire).
cat > ak3_tmp/anykernel.sh <<'AK3'
### AnyKernel3 Ramdisk Mod Script
## Sapphire / Sapphiren — SukiSU-Nova + SUSFS + KPM
properties() { '
kernel.string=Sapphire SukiSU-Nova + SUSFS + KPM
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=sapphiren
device.name2=sapphire
supported.versions=13-17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" -o -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot # for devices with init_boot ramdisk
    flash_boot # for devices with init_boot ramdisk
else
    dump_boot # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk
    write_boot # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
fi
## end boot install
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
