#!/usr/bin/env bash
# Integrate SukiSU-Nova AVC Log Spoofing (feature ID 10003) with the
# actual SUSFS GKI Android 13 / Linux 5.15 AVC state ABI.
set -euo pipefail

: "${KERNEL_DIR:?KERNEL_DIR is required}"
: "${WORK_DIR:=${GITHUB_WORKSPACE:-$PWD}}"
KSU_DIR="$KERNEL_DIR/SukiSU-Nova"
BASE_SHA="4bec532dd447e2852aa8932afa768255350c103a"
PR_SHA="119983f4dd8ca79dc69324cd358a73e104e35ab1"
AVC_SOURCE="$KERNEL_DIR/security/selinux/avc.c"
SUSFS_SOURCE="$KERNEL_DIR/fs/susfs.c"
SUSFS_HEADER="$KERNEL_DIR/include/linux/susfs.h"
SYMBOL="susfs_is_avc_log_spoofing_enabled"

[ -d "$KSU_DIR/.git" ] || { echo "[ERROR] SukiSU-Nova checkout not found: $KSU_DIR" >&2; exit 1; }
for source in "$AVC_SOURCE" "$SUSFS_SOURCE" "$SUSFS_HEADER"; do
  [ -s "$source" ] || { echo "[ERROR] Required SUSFS/SELinux source missing: $source" >&2; exit 1; }
done
CURRENT_SHA="$(git -C "$KSU_DIR" rev-parse HEAD)"
[ "$CURRENT_SHA" = "$BASE_SHA" ] || {
  echo "[ERROR] Unexpected SukiSU-Nova base: $CURRENT_SHA (expected $BASE_SHA)" >&2
  exit 1
}

# Detect and validate the real SUSFS state ABI after applying its patch.
AVC_ABI="$(python3 - "$KERNEL_DIR" "$AVC_SOURCE" "$SUSFS_SOURCE" "$SYMBOL" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
avc = Path(sys.argv[2]).read_text()
susfs = Path(sys.argv[3]).read_text()
symbol = sys.argv[4]

bool_def = re.search(rf"(?m)^\s*bool\s+{symbol}\s*(?:=\s*(?:false|0))?\s*;", avc)
bool_hook = re.search(rf"sad->tsid\s*==\s*susfs_ksu_sid\s*&&\s*{symbol}", avc)
bool_setter = re.search(rf"{symbol}\s*=\s*info\.enabled", susfs)
static_decl = re.search(rf"extern\s+struct\s+static_key_false\s+{symbol}\s*;", avc)
static_hook = re.search(rf"static_branch_likely\s*\(\s*&{symbol}\s*\)", avc)
static_definition = False
static_setter = False
if static_decl and static_hook:
    for path in root.rglob('*'):
        if not path.is_file() or path.suffix not in {'.c', '.h'}:
            continue
        if 'SukiSU-Nova' in path.parts or '.git' in path.parts:
            continue
        try:
            data = path.read_text(errors='ignore')
        except OSError:
            continue
        if re.search(rf"DEFINE_STATIC_KEY_FALSE\s*\(\s*{symbol}\s*\)", data):
            static_definition = True
        if re.search(rf"static_branch_(?:enable|disable)\s*\(\s*&{symbol}\s*\)", data):
            static_setter = True

if bool_def and bool_hook and bool_setter:
    if 'bypass_orig_flow:' not in avc:
        raise SystemExit('[ERROR] SUSFS bool AVC bypass label is missing')
    print('bool')
elif static_decl and static_hook and static_definition and static_setter:
    print('static_key_false')
else:
    occurrences = []
    for label, data in [('avc.c', avc), ('susfs.c', susfs)]:
        for line in data.splitlines():
            if symbol in line:
                occurrences.append(label + ': ' + line.strip())
    details = ' | '.join(occurrences[:8]) or 'symbol not found'
    raise SystemExit(
        '[ERROR] SUSFS AVC ABI is incomplete or unsupported. '
        f'bool_def={bool(bool_def)}, bool_hook={bool(bool_hook)}, bool_setter={bool(bool_setter)}, '
        f'static_decl={bool(static_decl)}, static_hook={bool(static_hook)}, '
        f'static_definition={static_definition}, static_setter={static_setter}. Details: {details}'
    )
PY
)"
echo "[OK] Detected SUSFS AVC ABI: $AVC_ABI"

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
[ -s "$PATCH_FILE" ] || { echo "[ERROR] AVC patch is empty" >&2; exit 1; }
git -C "$KSU_DIR" apply --check "$PATCH_FILE"
git -C "$KSU_DIR" apply "$PATCH_FILE"

# Match SukiSU's feature handler to the detected SUSFS ABI.
python3 - "$KSU_DIR/kernel/feature/avc_spoof.c" "$SUSFS_HEADER" "$AVC_ABI" "$SYMBOL" <<'PY'
from pathlib import Path
import re, sys
feature_path, header_path = Path(sys.argv[1]), Path(sys.argv[2])
abi, symbol = sys.argv[3], sys.argv[4]
feature = feature_path.read_text()
header = header_path.read_text()
if abi == 'bool':
    feature = feature.replace('#include <linux/jump_label.h>\n', '')
    if '#include <linux/compiler.h>' not in feature:
        anchor = '#include "include/klog.h"'
        if anchor not in feature:
            raise SystemExit('[ERROR] avc_spoof.c include anchor not found')
        feature = feature.replace(anchor, anchor + '\n#include <linux/compiler.h>', 1)
    feature, n1 = re.subn(r'static_key_enabled\(&susfs_is_avc_log_spoofing_enabled\)', f'READ_ONCE({symbol})', feature)
    feature, n2 = re.subn(r'static_branch_enable\(&susfs_is_avc_log_spoofing_enabled\);', f'WRITE_ONCE({symbol}, true);', feature)
    feature, n3 = re.subn(r'static_branch_disable\(&susfs_is_avc_log_spoofing_enabled\);', f'WRITE_ONCE({symbol}, false);', feature)
    if (n1, n2, n3) != (2, 1, 1):
        raise SystemExit(f'[ERROR] Unexpected SukiSU bool conversion shape: reads={n1}, enable={n2}, disable={n3}')
    decl = f'extern bool {symbol};'
    if decl not in header:
        pos = header.rfind('#endif')
        if pos < 0: raise SystemExit('[ERROR] SUSFS header guard terminator not found')
        header = header[:pos] + '\n/* Shared AVC spoof state used by SUSFS and SukiSU-Nova. */\n' + decl + '\n\n' + header[pos:]
    if decl not in header: raise SystemExit('[ERROR] SUSFS bool declaration missing from public header')
else:
    # PR #1058 already uses static_key_enabled/static_branch_enable/disable.
    # Export the existing SUSFS static key through susfs.h for SukiSU.
    if '#include <linux/jump_label.h>' not in header:
        guard = re.search(r'(?m)^#define\s+\w+', header)
        if guard:
            end = header.find('\n', guard.start())
            header = header[:end + 1] + '#include <linux/jump_label.h>\n' + header[end + 1:]
        else:
            header = '#include <linux/jump_label.h>\n' + header
    decl = f'extern struct static_key_false {symbol};'
    if decl not in header:
        pos = header.rfind('#endif')
        if pos < 0: raise SystemExit('[ERROR] SUSFS header guard terminator not found')
        header = header[:pos] + '\n/* Shared AVC spoof static key used by SUSFS and SukiSU-Nova. */\n' + decl + '\n\n' + header[pos:]
    if decl not in header: raise SystemExit('[ERROR] SUSFS static key declaration missing from public header')
feature_path.write_text(feature)
header_path.write_text(header)
print(f'[OK] SukiSU AVC feature handler matched SUSFS {abi} ABI')
PY

# Verify feature registration and the ABI-specific state operations.
grep -q 'KSU_FEATURE_AVC_SPOOF = 10003' "$KSU_DIR/kernel/include/uapi/feature.h"
grep -q 'name = "avc_spoof"' "$KSU_DIR/kernel/feature/avc_spoof.c"
grep -q 'ksu_avc_spoof_init();' "$KSU_DIR/kernel/ksu_main.c"
if [ "$AVC_ABI" = "bool" ]; then
  grep -q "READ_ONCE($SYMBOL)" "$KSU_DIR/kernel/feature/avc_spoof.c"
  grep -q "WRITE_ONCE($SYMBOL, true)" "$KSU_DIR/kernel/feature/avc_spoof.c"
  grep -q "WRITE_ONCE($SYMBOL, false)" "$KSU_DIR/kernel/feature/avc_spoof.c"
else
  grep -q "static_key_enabled(&$SYMBOL)" "$KSU_DIR/kernel/feature/avc_spoof.c"
  grep -q "static_branch_enable(&$SYMBOL)" "$KSU_DIR/kernel/feature/avc_spoof.c"
  grep -q "static_branch_disable(&$SYMBOL)" "$KSU_DIR/kernel/feature/avc_spoof.c"
fi

mkdir -p "$WORK_DIR"
cat > "$WORK_DIR/avc-spoof-build-proof.txt" <<EOF
SukiSU-Nova base: $BASE_SHA
AVC patch source: SukiSU-Nova PR #1058
AVC patch SHA: $PR_SHA
Feature ID: 10003
SUSFS branch: gki-android13-5.15
Detected SUSFS AVC ABI: $AVC_ABI
SUSFS AVC source: security/selinux/avc.c
SUSFS control source: fs/susfs.c
SukiSU feature handler: ABI-matched state operations
EOF

echo "[OK] AVC Log Spoofing handler registered (feature ID 10003)"
echo "[OK] SukiSU-Nova and SUSFS share the same Linux 5.15 AVC state"
echo "[INFO] PR #1058 Linux <5.10 SELinux-hide compatibility changes remain excluded"
