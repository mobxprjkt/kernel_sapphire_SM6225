#!/usr/bin/env bash
# Linux 5.15 compatibility fix for SukiSU-Nova AVC Log Spoofing.
# The SUSFS static key is defined in security/selinux/avc.c; it is not
# guaranteed to be declared in susfs_def.h. Export it through susfs.h.
set -euo pipefail

: "${KERNEL_DIR:?KERNEL_DIR is required}"
: "${WORK_DIR:=${GITHUB_WORKSPACE:-$PWD}}"

KSU_DIR="$KERNEL_DIR/SukiSU-Nova"
BASE_SHA="4bec532dd447e2852aa8932afa768255350c103a"
PR_SHA="119983f4dd8ca79dc69324cd358a73e104e35ab1"
AVC_SOURCE="$KERNEL_DIR/security/selinux/avc.c"
SUSFS_HEADER="$KERNEL_DIR/include/linux/susfs.h"

[ -d "$KSU_DIR/.git" ] || {
  echo "[ERROR] SukiSU-Nova checkout not found: $KSU_DIR" >&2
  exit 1
}
[ -s "$AVC_SOURCE" ] || {
  echo "[ERROR] SELinux AVC source missing: $AVC_SOURCE" >&2
  exit 1
}
[ -s "$SUSFS_HEADER" ] || {
  echo "[ERROR] SUSFS public header missing: $SUSFS_HEADER" >&2
  echo "[INFO] Verify that SUSFS kernel_patches/include/linux files were copied." >&2
  exit 1
}

CURRENT_SHA="$(git -C "$KSU_DIR" rev-parse HEAD)"
[ "$CURRENT_SHA" = "$BASE_SHA" ] || {
  echo "[ERROR] Unexpected SukiSU-Nova base: $CURRENT_SHA (expected $BASE_SHA)" >&2
  exit 1
}

# Correct check: SUSFS defines the jump-label key in avc.c.
# The old script searched only include/linux headers and stopped too early.
if ! grep -Eq 'DEFINE_STATIC_KEY_FALSE[[:space:]]*\([[:space:]]*susfs_is_avc_log_spoofing_enabled[[:space:]]*\)' "$AVC_SOURCE"; then
  echo "[ERROR] SUSFS AVC static key definition is absent from security/selinux/avc.c" >&2
  echo "[ERROR] Do not fabricate a key: re-check the selected SUSFS 5.15 patch." >&2
  exit 1
fi

# SukiSU-Nova PR #1058 includes <linux/susfs.h>. Export the existing
# static_key_false symbol there so avc_spoof.c can use static_branch_*().
python3 - "$SUSFS_HEADER" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()
symbol = "susfs_is_avc_log_spoofing_enabled"

if symbol not in s:
    if "#include <linux/jump_label.h>" not in s:
        # Add the jump-label type include immediately after the include guard.
        m = re.search(r"(^#define[^\n]*\n)", s, re.M)
        if not m:
            raise SystemExit("[ERROR] Could not locate SUSFS header include guard")
        s = s[:m.end()] + "\n#include <linux/jump_label.h>\n" + s[m.end():]
    declaration = (
        "\n/* SukiSU-Nova AVC Log Spoofing: key is defined in "
        "security/selinux/avc.c. */\n"
        "extern struct static_key_false susfs_is_avc_log_spoofing_enabled;\n"
    )
    # Insert before the final #endif to keep it inside the header guard.
    pos = s.rfind("#endif")
    if pos < 0:
        raise SystemExit("[ERROR] SUSFS header has no final #endif")
    s = s[:pos] + declaration + "\n" + s[pos:]
    p.write_text(s)

if "extern struct static_key_false susfs_is_avc_log_spoofing_enabled" not in s:
    raise SystemExit("[ERROR] Failed to export SUSFS AVC static key")
print("[OK] SUSFS AVC static key exported from include/linux/susfs.h")
PY

echo "[AVC] Fetching pinned SukiSU-Nova PR #1058"
git -C "$KSU_DIR" fetch --no-tags origin \
  refs/pull/1058/head:refs/remotes/origin/pr-1058

FETCHED_SHA="$(git -C "$KSU_DIR" rev-parse refs/remotes/origin/pr-1058)"
[ "$FETCHED_SHA" = "$PR_SHA" ] || {
  echo "[ERROR] PR #1058 head changed: $FETCHED_SHA (expected $PR_SHA)" >&2
  exit 1
}

PATCH_FILE="${WORK_DIR}/sukisu-avc-spoof-515.patch"
git -C "$KSU_DIR" diff --binary "$BASE_SHA" "$FETCHED_SHA" -- \
  kernel/extension/extension.c \
  kernel/feature/avc_spoof.c \
  kernel/feature/avc_spoof.h \
  kernel/include/uapi/feature.h \
  kernel/ksu_main.c \
  kernel/policy/feature.c > "$PATCH_FILE"

[ -s "$PATCH_FILE" ] || {
  echo "[ERROR] AVC patch is empty" >&2
  exit 1
}
git -C "$KSU_DIR" apply --check "$PATCH_FILE"
git -C "$KSU_DIR" apply "$PATCH_FILE"

grep -q 'KSU_FEATURE_AVC_SPOOF = 10003' "$KSU_DIR/kernel/include/uapi/feature.h"
grep -q 'name = "avc_spoof"' "$KSU_DIR/kernel/feature/avc_spoof.c"
grep -q 'ksu_avc_spoof_init();' "$KSU_DIR/kernel/ksu_main.c"
grep -q 'susfs_is_avc_log_spoofing_enabled' "$KSU_DIR/kernel/feature/avc_spoof.c"

mkdir -p "$WORK_DIR"
cat > "$WORK_DIR/avc-spoof-build-proof.txt" <<EOF
SukiSU-Nova base: $BASE_SHA
AVC patch source: SukiSU-Nova PR #1058
AVC patch SHA: $PR_SHA
Feature ID: 10003
SUSFS static key definition: security/selinux/avc.c
SUSFS static key declaration: include/linux/susfs.h
EOF

echo "[OK] AVC Log Spoofing handler registered (feature ID 10003)"
echo "[OK] SUSFS static key definition and public declaration verified"
echo "[INFO] PR #1058 Linux <5.10 SELinux-hide compatibility changes remain excluded"
