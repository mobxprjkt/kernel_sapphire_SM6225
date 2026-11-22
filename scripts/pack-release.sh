#!/usr/bin/env bash
# pack-release.sh — collect per-variant ZIPs or build AIO zip
# env: ZIP_MODE, BUILD_TYPE, DATE_TAG, KERNEL_VERSION
set -e

: "${ZIP_MODE:-per-variant}"
: "${BUILD_TYPE:-stable}"
: "${DATE_TAG:=$(date +'%Y%m%d')}"
: "${KERNEL_VERSION:-5.15.x}"

AK3_REPO="https://github.com/superuseryu/AnyKernel3"
mkdir -p ./release_zips

if [ "$ZIP_MODE" = "aio" ] || [ "$ZIP_MODE" = "both" ]; then
  [ "$BUILD_TYPE" = "testing" ] && SUFFIX="-testing" || SUFFIX=""
  # AIO layout retained; this project now publishes only the SukiSU-Nova build.
  _series=$(echo "${KERNEL_VERSION:-5.15.x}" | grep -oP '^\d+\.\d+' || echo "5.15")
  AIO_NAME="AK3-ALL-${_series}-$(date +'%Y-%m')${SUFFIX}.zip"

  echo "[AIO] Building the SukiSU-Nova AK3 bundle..."
  git clone --depth=1 "$AK3_REPO" ak3_aio
  cp "${GITHUB_WORKSPACE}/anykernel/anykernel.sh" ak3_aio/anykernel.sh

  # Extract the SukiSU-Nova Image and keep the AIO naming convention.
  for ARTIFACT_DIR in ./artifacts/*/; do
    ARTIFACT_ZIP=$(find "$ARTIFACT_DIR" -name "AK3-*.zip" | head -1)
    [ -f "$ARTIFACT_ZIP" ] || continue

    IMG_NAME="Image.gki.sksu"

    echo "[AIO] Extracting Image from: $ARTIFACT_ZIP → $IMG_NAME"
    unzip -o "$ARTIFACT_ZIP" "Image" -d /tmp/aio_extract/ 2>/dev/null || continue
    cp /tmp/aio_extract/Image "ak3_aio/${IMG_NAME}"
    cp /tmp/aio_extract/Image "ak3_aio/Image"
    rm -rf /tmp/aio_extract
  done

  echo "[AIO] Images collected:"
  ls -lh ak3_aio/Image.gki.sksu 2>/dev/null || { echo "[ERROR] No named images found"; exit 1; }

  cd ak3_aio
  zip -r9 "../release_zips/${AIO_NAME}" * -x .git/*
  cd ..
  rm -rf ak3_aio

  SIZE_MB=$(echo "scale=2; $(stat -c%s "./release_zips/${AIO_NAME}") / 1024 / 1024" | bc | sed 's/^\./0./')
  echo "✅ AIO zip: $AIO_NAME ($SIZE_MB MB)"
fi

if [ "$ZIP_MODE" = "per-variant" ] || [ "$ZIP_MODE" = "both" ]; then
  find ./artifacts -name "AK3-*.zip" -exec cp {} ./release_zips/ \;
  echo "Collected per-variant ZIPs:"
fi


ls -lh ./release_zips/
