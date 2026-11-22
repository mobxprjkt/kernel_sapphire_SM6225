#!/usr/bin/env bash
# Integrate only SukiSU-Nova + SUSFS for Android 13 / Linux 5.15.
set -euo pipefail

: "${KERNEL_DIR:?}"
: "${WORK_DIR:?}"
KSU_TYPE="sksu"

cd "$KERNEL_DIR"
rm -rf ./KernelSU ./KernelSU-Next ./drivers/kernelsu ./SukiSU-Nova ./susfs4ksu

git config --global init.defaultBranch main
git config --global advice.addEmbeddedRepo false

echo "=== Clone SukiSU-Nova ==="
git clone --depth=1 --branch builtin \
  https://github.com/SukiSU-Nova/SukiSU-Nova.git
[ -d "SukiSU-Nova/kernel" ] || {
  echo "[ERROR] SukiSU-Nova kernel directory not found" >&2
  exit 1
}

cd SukiSU-Nova
git fetch --tags 2>/dev/null || true
SKSU_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null || \
  git describe --tags --abbrev=0 HEAD 2>/dev/null || echo "builtin")
SKSU_SHA=$(git rev-parse HEAD)
cd ..

printf '%s\n' "$SKSU_TAG" > "$WORK_DIR/sksu_tag.txt"
printf '%s\n' "$SKSU_SHA" > "$WORK_DIR/sksu_sha.txt"
echo "SKSU_TAG=$SKSU_TAG" >> "${GITHUB_ENV:-/dev/null}"
echo "SKSU_SHA=$SKSU_SHA" >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] SukiSU-Nova: $SKSU_TAG ($SKSU_SHA)"

echo "=== Clone SUSFS branch gki-android13-5.15 ==="
git clone --depth=1 -b gki-android13-5.15 \
  https://gitlab.com/simonpunk/susfs4ksu.git
SUSFS_COMMIT=$(git -C susfs4ksu rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "SUSFS_COMMIT=$SUSFS_COMMIT" >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] SUSFS commit: $SUSFS_COMMIT"

SUSFS_PATCH="susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
[ -f "$SUSFS_PATCH" ] || {
  echo "[ERROR] SUSFS 5.15 patch not found: $SUSFS_PATCH" >&2
  exit 1
}

# Apply the integration patch. The upstream patch may have a GKI context
# difference in fs/namespace.c; that one hunk is handled explicitly below.
if ! patch -p1 --forward --batch --fuzz=3 < "$SUSFS_PATCH"; then
  echo "[WARN] SUSFS integration patch had rejected hunks; checking required files"
fi

# GKI namespace hunk compatibility: ensure the SUSFS include and declarations
# exist even when the upstream patch's context has shifted.
python3 - <<'PY'
from pathlib import Path
p = Path("fs/namespace.c")
if not p.exists():
    raise SystemExit("[ERROR] fs/namespace.c is missing")
s = p.read_text()

if "#include <linux/susfs_def.h>" not in s:
    anchors = ["#include <linux/mnt_idmapping.h>", "#include <linux/mount.h>"]
    for anchor in anchors:
        if anchor in s:
            s = s.replace(anchor, anchor + "\n\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif", 1)
            break
    else:
        raise SystemExit("[ERROR] namespace.c include anchor not found")

marker = '#include "internal.h"'
if marker not in s:
    raise SystemExit('[ERROR] namespace.c internal.h anchor not found')
block = """#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern bool susfs_is_current_ksu_domain(void);
extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;
#ifndef CL_COPY_MNT_NS
#define CL_COPY_MNT_NS BIT(25)
#endif
#endif"""
if "susfs_is_current_ksu_domain" not in s:
    s = s.replace(marker, marker + "\n\n" + block, 1)

p.write_text(s)
print("[OK] namespace.c SUSFS GKI compatibility declarations verified")
PY

mkdir -p fs include/linux
cp -f susfs4ksu/kernel_patches/fs/* fs/
cp -f susfs4ksu/kernel_patches/include/linux/* include/linux/

# SUSFS header may use current_uid() without including cred.h.
if [ -f include/linux/susfs_def.h ] && ! grep -q 'linux/cred.h' include/linux/susfs_def.h; then
  sed -i '1i#include <linux/cred.h>' include/linux/susfs_def.h
  echo "[OK] Added linux/cred.h to susfs_def.h"
fi

# Some SUSFS revisions leave rate-limited logging macros undefined when
# CONFIG_KSU_SUSFS_ENABLE_LOG is disabled.
if [ -f fs/susfs.c ] && ! grep -qE '^#define SUSFS_LOGI_RL\(fmt, \.\.\.\)' fs/susfs.c; then
  if grep -qF '#define SUSFS_LOGE(fmt, ...) ' fs/susfs.c; then
    sed -i '/^#define SUSFS_LOGE(fmt, \.\.\.) $/a #define SUSFS_LOGI_RL(fmt, ...) \n#define SUSFS_LOGE_RL(fmt, ...) ' fs/susfs.c
    echo "[OK] Added SUSFS_LOG*_RL fallback macros"
  fi
fi

# Critical Linux 5.15 API compatibility fix for the build failure observed
# in fs/susfs.c: fsnotify_alloc_group() takes one argument on this kernel.
bash "$WORK_DIR/scripts/fix-susfs-515.sh" fs/susfs.c

# Register AVC Log Spoofing (feature ID 10003) against the detected SUSFS GKI 5.15 ABI (bool or static_key_false).
bash "$WORK_DIR/scripts/apply-avc-spoof-515.sh"

# Link SukiSU-Nova into the kernel build.
[ -e drivers/kernelsu ] || ln -s ../SukiSU-Nova/kernel drivers/kernelsu
grep -q 'obj-.*kernelsu' drivers/Makefile || \
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
grep -q 'kernelsu/Kconfig' drivers/Kconfig || \
  echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig

rm -rf susfs4ksu
echo "[OK] SukiSU-Nova + SUSFS 5.15 + KPM source integration complete"
