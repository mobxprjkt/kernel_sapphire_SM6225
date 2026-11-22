#!/usr/bin/env bash
# Package the verified kernel Image as one directly flashable AnyKernel3 ZIP.
set -euo pipefail

: "${WORK_DIR:?WORK_DIR is required}"

IMAGE="${WORK_DIR}/out/dist/Image"
AK3_SOURCE="${WORK_DIR}/AnyKernel3"
PROOF="${WORK_DIR}/kpm-image-proof.txt"

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

[[ -s "$IMAGE" ]] || die "Kernel Image not found: $IMAGE"
[[ -s "$AK3_SOURCE/anykernel.sh" ]] || die "AnyKernel3/anykernel.sh is missing"
[[ -s "$AK3_SOURCE/tools/ak3-core.sh" ]] || die "AnyKernel3/tools/ak3-core.sh is missing"

# Refuse to package an Image that does not match the KPM verification proof.
bash "$WORK_DIR/scripts/patch-kpm-image.sh" verify "$IMAGE" "$PROOF"

VERSION_FILE="${WORK_DIR}/out/dist/kernel_version.txt"
RAW_VERSION="5.15"
if [[ -s "$VERSION_FILE" ]]; then
  RAW_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
KERNEL_VERSION="$(printf '%s' "$RAW_VERSION" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
[[ -n "$KERNEL_VERSION" ]] || KERNEL_VERSION="5.15"

ZIP_NAME="Sapphire-GKI-5.15-SukiSU-Nova-${KERNEL_VERSION}-flashable.zip"
STAGE="$(mktemp -d "${WORK_DIR}/.anykernel-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# Copy installer files directly to the archive root.
cp -a "$AK3_SOURCE/." "$STAGE/"
rm -f "$STAGE/README.md"
rm -rf "$STAGE/modules"
install -m 0644 "$IMAGE" "$STAGE/Image"

# Sanity-check the flashable ZIP layout before creating it.
[[ -s "$STAGE/Image" ]] || die "Image missing from installer staging directory"
[[ -s "$STAGE/anykernel.sh" ]] || die "anykernel.sh missing from installer staging directory"
[[ -s "$STAGE/META-INF/com/google/android/update-binary" ]] || die "AnyKernel3 update-binary missing"

rm -f "${WORK_DIR}/${ZIP_NAME}"
(
  cd "$STAGE"
  zip -qr9 "${WORK_DIR}/${ZIP_NAME}" . \
    -x './.git/*' './.git' './README.md' './modules/*'
)

# Confirm the archive has installer files at its root, not another nested ZIP.
unzip -Z1 "${WORK_DIR}/${ZIP_NAME}" | grep -Fxq 'Image' ||
  die "Flashable ZIP does not contain Image at archive root"
unzip -Z1 "${WORK_DIR}/${ZIP_NAME}" | grep -Fxq 'anykernel.sh' ||
  die "Flashable ZIP does not contain anykernel.sh at archive root"
if unzip -Z1 "${WORK_DIR}/${ZIP_NAME}" | grep -Eq '(^|/)[^/]+\.zip$'; then
  die "Nested ZIP detected inside flashable installer"
fi

echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] Created directly flashable installer: ${ZIP_NAME}"
