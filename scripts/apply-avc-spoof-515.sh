#!/usr/bin/env bash
# Adapt SukiSU-Nova AVC Log Spoofing feature ID 10003 to SUSFS GKI 5.15.
# The upstream GKI 5.15 SUSFS patch uses a shared bool, not a jump-label key.
set -euo pipefail

: "${KERNEL_DIR:?KERNEL_DIR is required}"
: "${WORK_DIR:=${GITHUB_WORKSPACE:-$PWD}}"

KSU_DIR="$KERNEL_DIR/SukiSU-Nova"
BASE_SHA="4bec532dd447e2852aa8932afa768255350c103a"
PR_SHA="119983f4dd8ca79dc69324cd358a73e104e35ab1"
AVC_SOURCE="$KERNEL_DIR/security/selinux/avc.c"
SUSFS_SOURCE="$KERNEL_DIR/fs/susfs.c"
SUSFS_HEADER="$KERNEL_DIR/include/linux/susfs.h"

[ -d "$KSU_DIR/.git" ] || {
  echo "[ERROR] SukiSU-Nova checkout not found: $KSU_DIR" >&2
  exit 1
}
for source in "$AVC_SOURCE" "$SUSFS_SOURCE" "$SUSFS_HEADER"; do
  [ -s "$source" ] || {
    echo "[ERROR] Required SUSFS/SELinux source missing: $source" >&2
    exit 1
  }
done

CURRENT_SHA="$(git -C "$KSU_DIR" rev-parse HEAD)"
[ "$CURRENT_SHA" = "$BASE_SHA" ] || {
  echo "[ERROR] Unexpected SukiSU-Nova base: $CURRENT_SHA (expected $BASE_SHA)" >&2
  exit 1
}

# Validate the actual SUSFS GKI 5.15 ABI before changing SukiSU.
# The file-scope bool may be explicitly initialized or rely on C zero-init.
python3 - "$AVC_SOURCE" "$SUSFS_SOURCE" <<'PY'
from pathlib import Path
import re, sys

avc = Path(sys.argv[1]).read_text()
susfs = Path(sys.argv[2]).read_text()
symbol = "susfs_is_avc_log_spoofing_enabled"

# A file-scope C bool is zero-initialized even when the patch omits
# an explicit "= false" initializer. Accept both valid definitions, but
# do not mistake an extern declaration for the actual storage definition.
definition = re.search(
    rf"(?m)^\s*bool\s+{symbol}\s*(?:=\s*(?:false|0))?\s*;",
    avc,
)
if not definition:
    matches = [line.strip() for line in avc.splitlines() if symbol in line]
    detail = " | ".join(matches[:5]) if matches else "symbol not found in avc.c"
    raise SystemExit(
        "[ERROR] SUSFS GKI 5.15 AVC bool definition not recognized in "
        f"security/selinux/avc.c ({detail})"
    )
if not re.search(rf"sad->tsid\s*==\s*susfs_ksu_sid\s*&&\s*{symbol}", avc):
    raise SystemExit("[ERROR] SUSFS AVC audit spoof hook is missing or has an unexpected form")
if "bypass_orig_flow:" not in avc:
    raise SystemExit("[ERROR] SUSFS AVC bypass label is missing")
if not re.search(rf"{symbol}\s*=\s*info\.enabled", susfs):
    raise SystemExit("[ERROR] SUSFS ioctl setter does not use the expected bool ABI")
print("[OK] SUSFS GKI 5.15 AVC bool definition, audit hook, and ioctl setter verified")
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

# PR #1058 expects static_key_false, but the selected SUSFS GKI 5.15 patch
# exports a plain bool and its ioctl setter writes that bool directly. Adapt
# only the SukiSU feature handler to the existing SUSFS ABI; do not invent a
# second state variable or convert the SUSFS setter to jump-label operations.
python3 - "$KSU_DIR/kernel/feature/avc_spoof.c" "$SUSFS_HEADER" <<'PY'
from pathlib import Path
import re, sys

feature_path = Path(sys.argv[1])
header_path = Path(sys.argv[2])
feature = feature_path.read_text()
header = header_path.read_text()
symbol = "susfs_is_avc_log_spoofing_enabled"

feature = feature.replace('#include <linux/jump_label.h>\n', '')
if '#include <linux/compiler.h>' not in feature:
    anchor = '#include "include/klog.h"'
    if anchor not in feature:
        raise SystemExit("[ERROR] avc_spoof.c include anchor not found")
    feature = feature.replace(anchor, anchor + '\n#include <linux/compiler.h>', 1)

feature, n1 = re.subn(
    r'static_key_enabled\(&susfs_is_avc_log_spoofing_enabled\)',
    f'READ_ONCE({symbol})', feature)
feature, n2 = re.subn(
    r'static_branch_enable\(&susfs_is_avc_log_spoofing_enabled\);',
    f'WRITE_ONCE({symbol}, true);', feature)
feature, n3 = re.subn(
    r'static_branch_disable\(&susfs_is_avc_log_spoofing_enabled\);',
    f'WRITE_ONCE({symbol}, false);', feature)
if (n1, n2, n3) != (2, 1, 1):
    raise SystemExit(f"[ERROR] Unexpected PR #1058 static-key API shape: reads={n1}, enable={n2}, disable={n3}")
if 'static_branch_' in feature or 'static_key_' in feature:
    raise SystemExit("[ERROR] Unconverted jump-label API remains in avc_spoof.c")
if f'READ_ONCE({symbol})' not in feature or f'WRITE_ONCE({symbol}, true)' not in feature or f'WRITE_ONCE({symbol}, false)' not in feature:
    raise SystemExit("[ERROR] Failed to adapt AVC feature handler to SUSFS bool ABI")
feature_path.write_text(feature)

# Expose the existing SUSFS bool to SukiSU's feature handler.
declaration = f'extern bool {symbol};'
if declaration not in header:
    pos = header.rfind('#endif')
    if pos < 0:
        raise SystemExit("[ERROR] SUSFS header include guard terminator not found")
    header = header[:pos] + '\n/* Shared AVC spoof state used by SUSFS and SukiSU-Nova. */\n' + declaration + '\n\n' + header[pos:]
    header_path.write_text(header)
if declaration not in header:
    raise SystemExit("[ERROR] Failed to export SUSFS AVC bool in include/linux/susfs.h")
print("[OK] SukiSU AVC handler adapted to SUSFS GKI 5.15 bool ABI")
PY

# Verify registration and ensure the handler uses the same SUSFS state.
grep -q 'KSU_FEATURE_AVC_SPOOF = 10003' "$KSU_DIR/kernel/include/uapi/feature.h"
grep -q 'name = "avc_spoof"' "$KSU_DIR/kernel/feature/avc_spoof.c"
grep -q 'ksu_avc_spoof_init();' "$KSU_DIR/kernel/ksu_main.c"
grep -q "READ_ONCE(susfs_is_avc_log_spoofing_enabled)" "$KSU_DIR/kernel/feature/avc_spoof.c"
grep -q "WRITE_ONCE(susfs_is_avc_log_spoofing_enabled, true)" "$KSU_DIR/kernel/feature/avc_spoof.c"
grep -q "WRITE_ONCE(susfs_is_avc_log_spoofing_enabled, false)" "$KSU_DIR/kernel/feature/avc_spoof.c"

mkdir -p "$WORK_DIR"
cat > "$WORK_DIR/avc-spoof-build-proof.txt" <<EOF
SukiSU-Nova base: $BASE_SHA
AVC patch source: SukiSU-Nova PR #1058
AVC patch SHA: $PR_SHA
Feature ID: 10003
SUSFS branch ABI: GKI android13 5.15 shared bool
SUSFS bool definition: security/selinux/avc.c
SUSFS AVC hook: security/selinux/avc.c avc_audit_post_callback
SUSFS ioctl setter: fs/susfs.c
SukiSU feature handler: READ_ONCE/WRITE_ONCE shared bool
EOF

echo "[OK] AVC Log Spoofing handler registered (feature ID 10003)"
echo "[OK] SukiSU-Nova and SUSFS share the same Linux 5.15 AVC spoof state"
echo "[INFO] PR #1058 Linux <5.10 SELinux-hide compatibility changes remain excluded"
