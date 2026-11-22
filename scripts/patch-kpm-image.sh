#!/usr/bin/env bash
# Inject KernelPatch kpimg into the built Sapphire Image.
# CONFIG_KPM=y alone only enables SukiSU-Nova's bridge; kpimg supplies runtime.
set -euo pipefail

MODE="${1:-}"
IMAGE="${2:-}"
PROOF="${3:-}"

KPM_PATCH_VERSION="0.13.9"
KPM_TOOLS_SHA256="6b5122046848865b1f68c04a45e34bbed81c9b535a42646a3ea423ce38a93aeb"
KPM_PAYLOAD_SHA256="396a20777668e85d674a23dd3945815f285332b5358be0bfc97297935e2d130b"
KPM_BASE_URL="https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/${KPM_PATCH_VERSION}"

die() { echo "[KPM ERROR] $*" >&2; exit 1; }

verify_image() {
  local image="$1" proof="$2" image_sha
  [[ -s "$image" ]] || die "Image missing or empty: $image"
  [[ -s "$proof" ]] || die "KPM runtime proof missing: $proof"
  image_sha="$(sha256sum "$image" | awk '{print $1}')"
  grep -Fxq "patched=true" "$proof" || die "KernelPatch inspector did not confirm patched=true"
  grep -Fxq "patch_version=${KPM_PATCH_VERSION}" "$proof" || die "KernelPatch version mismatch"
  grep -Fxq "tools_sha256=${KPM_TOOLS_SHA256}" "$proof" || die "kptools checksum proof mismatch"
  grep -Fxq "payload_sha256=${KPM_PAYLOAD_SHA256}" "$proof" || die "kpimg checksum proof mismatch"
  grep -Fxq "image_sha256=${image_sha}" "$proof" || die "Proof does not match this Image"
  echo "[KPM OK] KernelPatch ${KPM_PATCH_VERSION} runtime is embedded and verified"
  echo "[KPM OK] Image SHA-256: ${image_sha}"
}

case "$MODE" in
  patch)
    [[ -n "$IMAGE" && -n "$PROOF" ]] || die "Usage: $0 patch <Image> <proof-file>"
    [[ -s "$IMAGE" ]] || die "Input Image missing or empty: $IMAGE"
    IMAGE="$(realpath "$IMAGE")"
    PROOF="$(realpath -m "$PROOF")"
    STAGE="$(mktemp -d "$(dirname "$IMAGE")/.kpm-inject.XXXXXX")"
    trap 'rm -rf "$STAGE"' EXIT

    echo "[KPM] Downloading pinned KernelPatch ${KPM_PATCH_VERSION}"
    for asset in kptools-linux kpimg; do
      curl --retry 5 --retry-delay 3 --retry-all-errors -fLSs \
        "${KPM_BASE_URL}/${asset}" -o "${STAGE}/${asset}" ||
        die "Failed to download ${asset}"
    done

    tools_sha="$(sha256sum "$STAGE/kptools-linux" | awk '{print $1}')"
    payload_sha="$(sha256sum "$STAGE/kpimg" | awk '{print $1}')"
    [[ "$tools_sha" == "$KPM_TOOLS_SHA256" ]] || die "kptools-linux SHA-256 mismatch: ${tools_sha}"
    [[ "$payload_sha" == "$KPM_PAYLOAD_SHA256" ]] || die "kpimg SHA-256 mismatch: ${payload_sha}"
    chmod 755 "$STAGE/kptools-linux"

    input_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"
    echo "[KPM] Injecting kpimg into final Image"
    "$STAGE/kptools-linux" -p -s 123 -i "$IMAGE" \
      -k "$STAGE/kpimg" -o "$STAGE/Image" >"$STAGE/patch.log" 2>&1 || {
        cat "$STAGE/patch.log" >&2
        die "KernelPatch image injection failed"
      }

    [[ -s "$STAGE/Image" ]] || die "kptools did not produce output Image"
    cmp -s "$IMAGE" "$STAGE/Image" && die "Image is unchanged; refusing to claim KPM support"

    "$STAGE/kptools-linux" -l -i "$STAGE/Image" >"$STAGE/inspect.txt" 2>&1 ||
      die "KernelPatch image inspection failed"
    cat "$STAGE/inspect.txt"
    grep -Fxq "patched=true" "$STAGE/inspect.txt" ||
      die "Image inspector did not report patched=true"

    output_sha="$(sha256sum "$STAGE/Image" | awk '{print $1}')"
    {
      echo "patched=true"
      echo "patch_version=${KPM_PATCH_VERSION}"
      echo "tools_sha256=${KPM_TOOLS_SHA256}"
      echo "payload_sha256=${KPM_PAYLOAD_SHA256}"
      echo "input_sha256=${input_sha}"
      echo "image_sha256=${output_sha}"
      echo "superkey=123"
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
  *)
    die "Usage: $0 {patch|verify} <Image> <proof-file>"
    ;;
esac
