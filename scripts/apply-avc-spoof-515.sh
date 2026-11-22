#!/usr/bin/env bash
# Apply the AVC Log Spoofing feature from SukiSU-Nova PR #1058,
# selectively excluding the PR's Linux <5.10 SELinux-hide compatibility code.
set -euo pipefail

: "${KERNEL_DIR:?}"
KSU_DIR="$KERNEL_DIR/SukiSU-Nova"
BASE_SHA="4bec532dd447e2852aa8932afa768255350c103a"
PR_SHA="119983f4dd8ca79dc69324cd358a73e104e35ab1"

[ -d "$KSU_DIR/.git" ] || {
  echo "[ERROR] SukiSU-Nova git checkout not found: $KSU_DIR" >&2
  exit 1
}
CURRENT_SHA="$(git -C "$KSU_DIR" rev-parse HEAD)"
[ "$CURRENT_SHA" = "$BASE_SHA" ] || {
  echo "[ERROR] Unexpected SukiSU-Nova base: $CURRENT_SHA (expected $BASE_SHA)" >&2
  exit 1
}

# SUSFS must already be installed in the kernel tree before adding the AVC handler.
SUSFS_HEADER=""
for candidate in "$KERNEL_DIR/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs_def.h"; do
  if [ -f "$candidate" ] && grep -q 'susfs_is_avc_log_spoofing_enabled' "$candidate"; then
    SUSFS_HEADER="$candidate"
    break
  fi
done
[ -n "$SUSFS_HEADER" ] || {
  echo "[ERROR] SUSFS AVC static-key declaration not found in include/linux headers" >&2
  exit 1
}

echo "[AVC] Fetching pinned SukiSU-Nova PR #1058"
git -C "$KSU_DIR" fetch --no-tags origin \
  refs/pull/1058/head:refs/remotes/origin/pr-1058

FETCHED_SHA="$(git -C "$KSU_DIR" rev-parse refs/remotes/origin/pr-1058)"
[ "$FETCHED_SHA" = "$PR_SHA" ] || {
  echo "[ERROR] PR #1058 head changed: $FETCHED_SHA (expected $PR_SHA)" >&2
  exit 1
}

PATCH_FILE="${WORK_DIR:-$GITHUB_WORKSPACE}/sukisu-avc-spoof-515.patch"
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

printf '%s\n' \
  "SukiSU-Nova base: $BASE_SHA" \
  "AVC patch source: SukiSU-Nova PR #1058" \
  "AVC patch SHA: $PR_SHA" \
  "Feature ID: 10003" \
  "SUSFS hook: susfs_is_avc_log_spoofing_enabled" \
  > "${WORK_DIR:-$GITHUB_WORKSPACE}/avc-spoof-build-proof.txt"

echo "[OK] AVC Log Spoofing handler registered (feature ID 10003)"
echo "[INFO] PR #1058 SELinux-hide 5.4-only changes were intentionally excluded"
