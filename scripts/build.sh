#!/usr/bin/env bash
# Build a single GKI Android 13 / Linux 5.15 Image with SukiSU-Nova + SUSFS + KPM.
set -euo pipefail

: "${KERNEL_SRC:?}"
: "${WORK_DIR:?}"
: "${DEFCONFIG:?}"
: "${CLANG_DIR:?}"

OUT_DIR="${WORK_DIR}/out"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-mobxprjkt}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-GitHub-Actions}"
export PATH="${CLANG_DIR}/bin:$PATH"

MAKE_FLAGS=(
  -j"$(nproc)"
  O="${OUT_DIR}/dist"
  ARCH=arm64
  SUBARCH=arm64
  LLVM=1
  LLVM_IAS=1
  CC="ccache clang"
  HOSTCC="ccache clang"
  HOSTCXX="ccache clang++"
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  STRIP=llvm-strip
  OBJSIZE=llvm-size
  READELF=llvm-readelf
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER"
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST"
  LOCALVERSION=""
  BRANCH=android13-5.15-lts
  KMI_GENERATION=8
)

mkdir -p "$OUT_DIR/dist"
export CCACHE_DIR="${CCACHE_DIR:-${WORK_DIR}/.ccache}"
export CCACHE_BASEDIR="${WORK_DIR}"
export CCACHE_COMPILERCHECK=content
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
mkdir -p "$CCACHE_DIR"
ccache --zero-stats || true
cd "$KERNEL_SRC"

# Enforce the real source series; no Linux 6.12 release spoofing/backport stack.
VERSION_LINE=$(awk '/^VERSION /{v=$3} /^PATCHLEVEL /{p=$3} END{if(v && p) print v "." p}' Makefile)
[ "$VERSION_LINE" = "5.15" ] || {
  echo "[ERROR] Expected Linux 5.15 source, found ${VERSION_LINE:-unknown}" >&2
  exit 1
}
sed -i 's/-dirty//' scripts/setlocalversion
printf '+\n' > .scmversion

echo "[CONFIG] Generate $DEFCONFIG"
make "${MAKE_FLAGS[@]}" "$DEFCONFIG"
./scripts/config --file "$OUT_DIR/dist/.config" \
  -e LTO_CLANG -d LTO_NONE -e LTO_CLANG_THIN -d LTO_CLANG_FULL -e THINLTO
make "${MAKE_FLAGS[@]}" olddefconfig

echo "[CHECK] Required feature config"
for symbol in CONFIG_KSU CONFIG_KPM CONFIG_KALLSYMS CONFIG_KALLSYMS_ALL CONFIG_KSU_SUSFS; do
  grep -qx "$symbol=y" "$OUT_DIR/dist/.config" || {
    echo "[ERROR] $symbol is not enabled after olddefconfig" >&2
    exit 1
  }
done

# SukiSU-Nova builtin branch compiles KPM implementation through ksu_main.c
# when KSU_CAN_USE_KPM is enabled. Fail if the implementation is absent.
KSU_DIR="$KERNEL_SRC/drivers/kernelsu"
for source in \
  "$KSU_DIR/extension/kpm.c" \
  "$KSU_DIR/extension/kpm/kpm.c" \
  "$KSU_DIR/extension/kpm.h"; do
  [ -s "$source" ] || {
    echo "[ERROR] Required SukiSU KPM source missing: $source" >&2
    exit 1
  }
done
printf '%s\n' \
  'CONFIG_KSU=y' 'CONFIG_KPM=y' 'CONFIG_KALLSYMS=y' \
  'CONFIG_KALLSYMS_ALL=y' 'CONFIG_KSU_SUSFS=y' \
  "SukiSU-Nova SHA: ${SKSU_SHA:-unknown}" \
  > "$WORK_DIR/kpm-build-proof.txt"
echo "[OK] KPM config and implementation sources verified"

AVC_SOURCE="$KERNEL_SRC/drivers/kernelsu/feature/avc_spoof.c"
AVC_HEADER="$KERNEL_SRC/drivers/kernelsu/feature/avc_spoof.h"
for source in "$AVC_SOURCE" "$AVC_HEADER"; do
  [ -s "$source" ] || {
    echo "[ERROR] AVC Log Spoofing source missing: $source" >&2
    exit 1
  }
done
grep -q 'KSU_FEATURE_AVC_SPOOF = 10003' "$KERNEL_SRC/drivers/kernelsu/include/uapi/feature.h"
grep -q 'ksu_avc_spoof_init();' "$KERNEL_SRC/drivers/kernelsu/ksu_main.c"
echo "[OK] AVC Log Spoofing feature ID 10003 and handler source verified"

echo "[BUILD] Image only — no unrelated optional modules"
LOG="${WORK_DIR}/build.log"
if ! make "${MAKE_FLAGS[@]}" Image 2>&1 | tee "$LOG"; then
  echo "[FAIL] Kernel build failed; last 120 lines:"
  tail -120 "$LOG"
  exit 1
fi

IMAGE="$OUT_DIR/dist/arch/arm64/boot/Image"
[ -f "$IMAGE" ] || { echo "[ERROR] Image not produced" >&2; exit 1; }
cp "$IMAGE" "$OUT_DIR/dist/Image"
echo "[OK] Image ready: $OUT_DIR/dist/Image"
echo "[CCACHE] Statistics after build:"
ccache --show-stats || true
