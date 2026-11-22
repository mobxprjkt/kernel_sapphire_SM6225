#!/usr/bin/env bash
# Apply the known Linux 5.15 fsnotify API compatibility fix to SUSFS.
set -euo pipefail

FILE="${1:-fs/susfs.c}"
[ -f "$FILE" ] || {
  echo "[ERROR] SUSFS source not found: $FILE" >&2
  exit 1
}

python3 - "$FILE" <<'PY'
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

# Linux 5.15 declares:
#   fsnotify_alloc_group(const struct fsnotify_ops *ops)
# Newer SUSFS revisions may call it with the newer two-argument form.
pattern = re.compile(
    r'fsnotify_alloc_group\(\s*(&[A-Za-z_][A-Za-z0-9_]*)\s*,\s*0\s*\)'
)
src, count = pattern.subn(r'fsnotify_alloc_group(\1)', src)

# Refuse unknown multi-argument forms instead of silently building a bad patch.
if re.search(r'fsnotify_alloc_group\([^;]*,\s*[^)]*\)', src, re.S):
    print("[ERROR] Multi-argument fsnotify_alloc_group call remains; Linux 5.15 requires exactly one argument", file=sys.stderr)
    sys.exit(1)

if count:
    print(f"[OK] SUSFS 5.15: converted {count} fsnotify_alloc_group call(s) to the 1-argument API")
elif "fsnotify_alloc_group" in src:
    print("[OK] SUSFS already uses the Linux 5.15 fsnotify_alloc_group API")
else:
    print("[WARN] fsnotify_alloc_group not present in SUSFS source")

open(path, "w", encoding="utf-8").write(src)
PY
