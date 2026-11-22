#!/usr/bin/env bash
set -euo pipefail
: "${WORK_DIR:=${GITHUB_WORKSPACE:?}}"
: "${KERNEL_SRC:=${WORK_DIR}/kernel_src}"
GKI_REPO="https://github.com/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire.git"
GKI_BRANCH="lineage-23.2-caf"

rm -rf "$KERNEL_SRC"
mkdir -p "$(dirname "$KERNEL_SRC")"
echo "[GKI] Cloning $GKI_REPO ($GKI_BRANCH)"
git clone --depth=1 --recursive --branch "$GKI_BRANCH" "$GKI_REPO" "$KERNEL_SRC"
[ -f "$KERNEL_SRC/Makefile" ] || { echo "[ERROR] Kernel Makefile missing" >&2; exit 1; }
[ -f "$KERNEL_SRC/arch/arm64/configs/vendor/sapphire_defconfig" ] || {
  echo "[ERROR] vendor/sapphire_defconfig missing from selected source branch" >&2
  exit 1
}
echo "[OK] Kernel source and vendor/sapphire_defconfig found"
