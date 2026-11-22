#!/usr/bin/env bash
# Build both kpimg and kptools from the same pinned SukiSU-Nova KernelPatch source.
# This keeps KernelPatch's ARM64 supercall ABI aligned with SukiSU-Nova bridge ABI v2.
set -euo pipefail

MODE="${1:-}"
IMAGE="${2:-}"
PROOF="${3:-}"
WORK_DIR="${WORK_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SUKISU_KPM_BRIDGE_HEADER="${SUKISU_KPM_BRIDGE_HEADER:-${KERNEL_SRC:-}/drivers/kernelsu/extension/kpm/bridge.h}"

KP_REPO="https://github.com/SukiSU-Nova/SukiSU_KernelPatch_patch.git"
KP_REF="main"
KP_COMMIT="1c5b608916357ac86a94cc736e235db1fac4a29d"

 die() { echo "[KPM ERROR] $*" >&2; exit 1; }

verify_image() {
  local image="$1" proof="$2" image_sha
  [[ -s "$image" ]] || die "Image missing or empty: $image"
  [[ -s "$proof" ]] || die "KPM proof missing: $proof"
  image_sha="$(sha256sum "$image" | awk '{print $1}')"
  grep -Fxq 'patched=true' "$proof" || die "KernelPatch inspector did not confirm patched=true"
  grep -Fxq "kp_repo=${KP_REPO}" "$proof" || die "Unexpected KernelPatch repository"
  grep -Fxq "kp_ref=${KP_REF}" "$proof" || die "KernelPatch ref mismatch"
  grep -Fxq "kp_commit=${KP_COMMIT}" "$proof" || die "KernelPatch source commit mismatch"
  grep -Fxq 'supercall_abi=2' "$proof" || die "KernelPatch supercall ABI proof missing"
  grep -Fxq "image_sha256=${image_sha}" "$proof" || die "Proof does not match this Image"
  echo "[KPM OK] SukiSU-Nova ABI-v2 KernelPatch payload is embedded and verified"
  echo "[KPM OK] Image SHA-256: ${image_sha}"
}

case "$MODE" in
  patch)
    [[ -n "$IMAGE" && -n "$PROOF" ]] || die "Usage: $0 patch <Image> <proof-file>"
    [[ -s "$IMAGE" ]] || die "Input Image missing or empty: $IMAGE"
    command -v cmake >/dev/null || die "cmake is required to build matching kptools"
    command -v aarch64-linux-gnu-gcc >/dev/null || die "aarch64-linux-gnu-gcc is required to build matching kpimg"
    IMAGE="$(realpath "$IMAGE")"
    PROOF="$(realpath -m "$PROOF")"
    STAGE="$(mktemp -d "${WORK_DIR}/.kpm-build.XXXXXX")"
    trap 'rm -rf "$STAGE"' EXIT

    echo "[KPM] Cloning pinned SukiSU-Nova KernelPatch source"
    git clone --quiet --depth=1 --recursive "$KP_REPO" "$STAGE/kernelpatch"
    actual_commit="$(git -C "$STAGE/kernelpatch" rev-parse HEAD)"
    [[ "$actual_commit" == "$KP_COMMIT" ]] || die "KernelPatch commit changed: expected ${KP_COMMIT}, got ${actual_commit}"

    BRIDGE="$STAGE/kernelpatch/kernel/patch/sukisu/supercall.h"
    [[ -s "$BRIDGE" ]] || die "KernelPatch SukiSU supercall implementation is missing"
    grep -q 'SUKISU_KPM_ABI_VERSION 2' "$BRIDGE" || die "KernelPatch supercall ABI is not v2"
    for magic in 0x53554b504d000002UL 0x4b504d4252494447UL 0x53554b494e544552UL; do
      grep -q "$magic" "$BRIDGE" || die "KernelPatch ABI magic mismatch: $magic"
      [[ -s "$SUKISU_KPM_BRIDGE_HEADER" ]] || die "SukiSU-Nova bridge header missing: $SUKISU_KPM_BRIDGE_HEADER"
      grep -q "$magic" "$SUKISU_KPM_BRIDGE_HEADER" || die "SukiSU-Nova / KernelPatch ABI magic mismatch: $magic"
    done
    grep -q 'SUKISU_KPM_ABI_VERSION 2' "$SUKISU_KPM_BRIDGE_HEADER" || die "SukiSU-Nova bridge ABI is not v2"

    echo "[KPM] Preparing ARM64 freestanding kpimg compiler flags"
    KP_MAKEFILE="$STAGE/kernelpatch/kernel/Makefile"
    [[ -s "$KP_MAKEFILE" ]] || die "KernelPatch kernel Makefile is missing"
    python3 - "$KP_MAKEFILE" <<'PYMAKE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
anchor = "CFLAGS += -DANDROID"
lines = s.splitlines()
if lines.count(anchor) != 1:
    raise SystemExit(f"[KPM ERROR] Expected exactly one exact ARM64 CFLAGS line, found {lines.count(anchor)}")

# kpimg is a freestanding, fixed-address ARM64 payload. Ubuntu's cross-GCC
# may default to PIE; that emits GOT/PLT relocations which kpimg.lds rejects.
# Disable both stack protector and PIC/PIE for ARM64 C compilation only.
required = [
    "CFLAGS += -fno-stack-protector",
    "CFLAGS += -fno-pic -fno-pie",
]
index = lines.index(anchor)
arm_end = next((i for i in range(index + 1, len(lines)) if lines[i].startswith("X86_CFLAGS")), len(lines))
arm_section = lines[index + 1:arm_end]
for flag in required:
    if flag not in arm_section:
        lines.insert(index + 1, flag)
        index += 1
        arm_end += 1
s = "\\n".join(lines) + "\\n"
p.write_text(s)

# Assert both flags are in ARM64 CFLAGS before the first X86_CFLAGS declaration.
arm_section = s.split(anchor, 1)[1].split("X86_CFLAGS", 1)[0]
for flag in required:
    if flag not in arm_section:
        raise SystemExit(f"[KPM ERROR] Missing ARM64 compiler flag: {flag}")

PYMAKE
    grep -Fq 'CFLAGS += -fno-stack-protector' "$KP_MAKEFILE" || die "ARM64 stack protector flag was not inserted"
    grep -Fq 'CFLAGS += -fno-pic -fno-pie' "$KP_MAKEFILE" || die "ARM64 no-PIC/no-PIE flags were not inserted"
    echo "[KPM] Verified ARM64 CFLAGS: -fno-stack-protector -fno-pic -fno-pie"
    echo "[KPM] Building fixed-address freestanding ARM64 kpimg without stack protector or GOT/PLT"
    # KernelPatch checks TARGET_COMPILE at Makefile parse time. Export it into
    # the make process as well as passing it on the command line so wrappers
    # and nested make invocations inherit the same bare-metal cross prefix.
    export TARGET_COMPILE="aarch64-linux-gnu-"
    [[ "$TARGET_COMPILE" == "aarch64-linux-gnu-" ]] || die "Invalid TARGET_COMPILE: $TARGET_COMPILE"
    make -C "$STAGE/kernelpatch/kernel" TARGET_COMPILE="$TARGET_COMPILE" -j"$(nproc)"
    # A freestanding kpimg must not retain compiler-generated stack-check
    # runtime calls. Inspect every ARM64 object before allowing the final link.
    OBJECT_SYMBOLS="$STAGE/kernelpatch/kernel/arm64-object-undefined-symbols.txt"
    find "$STAGE/kernelpatch/kernel" -type f -name '*.o' -print0 \
      | xargs -0 -r aarch64-linux-gnu-nm -u > "$OBJECT_SYMBOLS" || true
    if grep -E '__stack_chk_(guard|fail)' "$OBJECT_SYMBOLS" > "$STAGE/kernelpatch/kernel/stack-protector-refs.txt"; then
      cat "$STAGE/kernelpatch/kernel/stack-protector-refs.txt" >&2
      die "ARM64 kpimg objects still reference stack protector runtime; refusing to link/package"
    fi
    echo "[KPM OK] No __stack_chk_guard/__stack_chk_fail references in ARM64 kpimg objects"
    KPIMG="$STAGE/kernelpatch/kernel/kpimg"
    [[ -s "$KPIMG" ]] || die "Matching ARM64 kpimg was not produced"

    echo "[KPM] Building kptools from the same source revision"
    cmake -S "$STAGE/kernelpatch/tools" -B "$STAGE/tools-build" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$STAGE/tools-build" --parallel "$(nproc)"
    KPT="$STAGE/tools-build/kptools"
    [[ -x "$KPT" ]] || die "Matching kptools binary was not produced"

    input_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"
    echo "[KPM] Injecting ABI-v2 kpimg into final Image"
    "$KPT" -p -s 123 -i "$IMAGE" -k "$KPIMG" -o "$STAGE/Image" >"$STAGE/patch.log" 2>&1 || {
      cat "$STAGE/patch.log" >&2
      die "KernelPatch image injection failed"
    }
    [[ -s "$STAGE/Image" ]] || die "kptools produced an empty Image"
    cmp -s "$IMAGE" "$STAGE/Image" && die "Image unchanged; refusing to claim KPM runtime injection"

    "$KPT" -l -i "$STAGE/Image" >"$STAGE/inspect.txt" 2>&1 || {
      cat "$STAGE/inspect.txt" >&2
      die "KernelPatch image inspection failed"
    }
    cat "$STAGE/inspect.txt"
    grep -Fxq 'patched=true' "$STAGE/inspect.txt" || die "Inspector did not report patched=true"

    output_sha="$(sha256sum "$STAGE/Image" | awk '{print $1}')"
    kpimg_sha="$(sha256sum "$KPIMG" | awk '{print $1}')"
    tools_sha="$(sha256sum "$KPT" | awk '{print $1}')"
    {
      echo 'patched=true'
      echo "kp_repo=${KP_REPO}"
      echo "kp_ref=${KP_REF}"
      echo "kp_commit=${KP_COMMIT}"
      echo "kpimg_sha256=${kpimg_sha}"
      echo "kptools_sha256=${tools_sha}"
      echo "input_sha256=${input_sha}"
      echo "image_sha256=${output_sha}"
      echo 'superkey=123'
      echo 'supercall_abi=2'
      cat "$STAGE/inspect.txt"
    } > "$STAGE/kpm-image-proof.txt"
    mv "$STAGE/Image" "$IMAGE"
    mv "$STAGE/kpm-image-proof.txt" "$PROOF"
    verify_image "$IMAGE" "$PROOF"
    ;;
  verify)
    [[ -n "$IMAGE" && -n "$PROOF" ]] || die "Usage: $0 verify <Image> <proof-file>"
    verify_image "$IMAGE" "$PROOF"
    ;;
  *) die "Usage: $0 {patch|verify} <Image> <proof-file>" ;;
esac
