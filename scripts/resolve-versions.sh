#!/usr/bin/env bash
# ============================================================
# resolve-versions.sh
# Resolve kernel versions, KSU metadata, Manager artifacts
# and GitHub Release information.
#
# Required:
#   bash, curl, jq, find, sed, date
#
# Environment:
#   BUILD_TYPE
#   WORKFLOW_TYPE
#   GITHUB_TOKEN
#   GITHUB_REPOSITORY
#   GITHUB_ENV
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

BUILD_TYPE="${BUILD_TYPE:-stable}"
WORKFLOW_TYPE="${WORKFLOW_TYPE:-aio}"
ARTIFACT_DIR="./artifacts"

SUSFS_DEFAULT="v1.5.2+_R27"

KSUN_REPO="KernelSU-Next/KernelSU-Next"
KSUN_WORKFLOW="build-manager-ci.yml"
KSUN_BRANCH="dev"

SKSU_REPO="SukiSU-Nova/SukiSU-Nova"
SKSU_WORKFLOW="manager.yml"
SKSU_BRANCH="main"

GITHUB_API="https://api.github.com"

# ------------------------------------------------------------
# Dependency checks
# ------------------------------------------------------------

for cmd in curl jq find sed date; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Missing dependency: $cmd" >&2
        exit 1
    fi
done

if [ ! -d "$ARTIFACT_DIR" ]; then
    echo "[WARN] Artifact directory not found: $ARTIFACT_DIR"
    mkdir -p "$ARTIFACT_DIR"
fi

# ------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------

first_file() {
    local pattern="$1"
    local file=""

    file=$(find "$ARTIFACT_DIR" -type f -name "$pattern" -print -quit 2>/dev/null || true)

    printf '%s' "$file"
}

first_gki_file() {
    local pattern="$1"
    local file=""

    file=$(find "$ARTIFACT_DIR" -type f \
        -path '*gki-*' \
        -name "$pattern" \
        -print -quit 2>/dev/null || true)

    printf '%s' "$file"
}

read_file() {
    local file="$1"
    local fallback="${2:-}"

    if [ -n "$file" ] && [ -f "$file" ]; then
        cat "$file"
    else
        printf '%s' "$fallback"
    fi
}

read_trimmed() {
    local file="$1"
    local fallback="${2:-}"

    if [ -n "$file" ] && [ -f "$file" ]; then
        tr -d '[:space:]' < "$file"
    else
        printf '%s' "$fallback"
    fi
}

api_get() {
    local url="$1"

    [ -n "${GITHUB_TOKEN:-}" ] || return 1

    curl -fsSL \
        --retry 2 \
        --retry-delay 2 \
        --max-time 20 \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url"
}

# ------------------------------------------------------------
# Kernel version information
# ------------------------------------------------------------

VERSION_FILE=$(first_file "kernel_version.txt")
UNAME_FILE=$(first_file "kernel_uname.txt")

KERNEL_VERSION=$(read_file "$VERSION_FILE" "5.15.x")
KERNEL_UNAME=$(read_file "$UNAME_FILE" "$KERNEL_VERSION")

GKI_VERSION_FILE=$(first_gki_file "kernel_version.txt")
GKI_UNAME_FILE=$(first_gki_file "kernel_uname.txt")

KERNEL_VERSION_GKI=$(read_file "$GKI_VERSION_FILE" "")
KERNEL_UNAME_GKI=$(read_file "$GKI_UNAME_FILE" "$KERNEL_VERSION_GKI")

# ------------------------------------------------------------
# SUSFS version
# ------------------------------------------------------------

echo "[INFO] Resolving SUSFS version..."

_susfs_raw=""

_susfs_json=$(api_get \
    "${GITHUB_API}/repos/sidex15/susfs4ksu-module/tags" 2>/dev/null) || _susfs_json=""

if [ -n "$_susfs_json" ]; then
    _susfs_raw=$(echo "$_susfs_json" | jq -r '.[0].name // empty' 2>/dev/null || true)
fi

SUSFS_VERSION="${_susfs_raw:-$SUSFS_DEFAULT}"

# ------------------------------------------------------------
# KSU version metadata
# ------------------------------------------------------------

KSUN_TAG_FILE=$(first_file "ksun_tag.txt")
SKSU_TAG_FILE=$(first_file "sksu_tag.txt")

KSUN_VERSION_FILE=$(first_file "ksun_version.txt")
SKSU_VERSION_FILE=$(first_file "sksu_version.txt")

KSUN_SHA_FILE=$(first_file "ksun_sha.txt")
SKSU_SHA_FILE=$(first_file "sksu_sha.txt")

KSUN_TAG=$(read_trimmed "$KSUN_TAG_FILE" "unknown")
SKSU_TAG=$(read_trimmed "$SKSU_TAG_FILE" "unknown")

KSUN_VERSION=$(read_trimmed "$KSUN_VERSION_FILE" "")
SKSU_VERSION=$(read_trimmed "$SKSU_VERSION_FILE" "")

KSUN_SHA=$(read_trimmed "$KSUN_SHA_FILE" "")
SKSU_SHA=$(read_trimmed "$SKSU_SHA_FILE" "")

# ------------------------------------------------------------
# Generic Manager workflow resolver
# ------------------------------------------------------------

find_manager_run() {
    local repo="$1"
    local workflow="$2"
    local branch="$3"
    local sha="$4"

    local page runs run_id count url

    # Exact SHA search
    if [ -n "$sha" ]; then

        echo "[INFO] Searching ${repo} SHA: ${sha}" >&2

        for page in 1 2 3; do

            url="${GITHUB_API}/repos/${repo}/actions/workflows/${workflow}/runs?status=success&branch=${branch}&per_page=20&page=${page}"

            runs=$(api_get "$url" 2>/dev/null) || break

            run_id=$(echo "$runs" | jq -r --arg sha "$sha" '
                (.workflow_runs // [])[]
                | select(.head_sha == $sha)
                | select(.conclusion == "success")
                | .id
            ' 2>/dev/null | head -1 || true)

            run_id="${run_id//[[:space:]]/}"

            if [ -n "$run_id" ]; then
                echo "[OK] Exact SHA matched: ${run_id}" >&2
                printf '%s' "$run_id"
                return 0
            fi

            count=$(echo "$runs" | jq -r '
                (.workflow_runs // []) | length
            ' 2>/dev/null || echo 0)

            [ "${count:-0}" -lt 20 ] && break

        done
    fi

    # Fallback: latest successful run
    echo "[WARN] Exact SHA not found for ${repo}" >&2
    echo "[INFO] Trying latest successful ${branch} build..." >&2

    url="${GITHUB_API}/repos/${repo}/actions/workflows/${workflow}/runs?status=success&branch=${branch}&per_page=1"

    runs=$(api_get "$url" 2>/dev/null) || return 1

    run_id=$(echo "$runs" | jq -r '
        .workflow_runs[0].id // empty
    ' 2>/dev/null || true)

    run_id="${run_id//[[:space:]]/}"

    if [ -n "$run_id" ]; then
        printf '%s' "$run_id"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Generic Manager artifact resolver
# ------------------------------------------------------------

resolve_manager() {
    local prefix="$1"
    local repo="$2"
    local workflow="$3"
    local branch="$4"
    local sha="$5"
    local manager_name="$6"
    local spoofed_name="$7"
    local fallback_url="$8"

    local run_id=""
    local artifacts=""
    local manager_id=""
    local spoofed_id=""
    local run_sha=""
    local manager_url="$fallback_url"

    echo ""
    echo "[INFO] Resolving ${prefix} Manager..."

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        echo "[WARN] GITHUB_TOKEN unavailable; skipping ${prefix} Manager."
    else

        run_id=$(find_manager_run \
            "$repo" \
            "$workflow" \
            "$branch" \
            "$sha") || run_id=""

    fi

    if [ -n "$run_id" ]; then

        manager_url="https://github.com/${repo}/actions/runs/${run_id}"

        echo "[INFO] ${prefix} run: ${run_id}"

        # Fetch artifact list once
        artifacts=$(api_get \
            "${GITHUB_API}/repos/${repo}/actions/runs/${run_id}/artifacts" \
            2>/dev/null) || artifacts=""

        if [ -n "$artifacts" ]; then

            manager_id=$(echo "$artifacts" | jq -r \
                --arg name "$manager_name" '
                (.artifacts // [])[]
                | select(.name == $name)
                | select(.expired == false)
                | .id
            ' 2>/dev/null | head -1 || true)

            spoofed_id=$(echo "$artifacts" | jq -r \
                --arg name "$spoofed_name" '
                (.artifacts // [])[]
                | select(.name == $name)
                | select(.expired == false)
                | .id
            ' 2>/dev/null | head -1 || true)

        fi

        # Verify upstream run SHA
        run_info=$(api_get \
            "${GITHUB_API}/repos/${repo}/actions/runs/${run_id}" \
            2>/dev/null) || run_info=""

        if [ -n "$run_info" ]; then
            run_sha=$(echo "$run_info" | jq -r '.head_sha // empty' 2>/dev/null || true)
        fi

        if [ -n "$sha" ] && [ -n "$run_sha" ] && [ "$sha" != "$run_sha" ]; then
            echo "[WARN] ${prefix} Manager SHA mismatch!"
            echo "[WARN] Kernel SHA : ${sha}"
            echo "[WARN] Manager SHA: ${run_sha}"
            echo "[WARN] This is a fallback Manager, not an exact match."
        fi

    else
        echo "[WARN] No successful ${prefix} Manager run found."
    fi

    # Export variables dynamically
    printf -v "${prefix}_MANAGER_URL" '%s' "$manager_url"
    printf -v "${prefix}_MANAGER_ARTIFACT_ID" '%s' "$manager_id"
    printf -v "${prefix}_MANAGER_SPOOFED_ARTIFACT_ID" '%s' "$spoofed_id"
    printf -v "${prefix}_MANAGER_RUN_SHA" '%s' "$run_sha"

    echo "[INFO] ${prefix} Manager URL: ${manager_url}"

    if [ -n "$manager_id" ]; then
        echo "[OK] ${prefix} Manager artifact: ${manager_id}"
    else
        echo "[WARN] ${prefix} Manager artifact unavailable."
    fi

    if [ -n "$spoofed_id" ]; then
        echo "[OK] ${prefix} Spoofed artifact: ${spoofed_id}"
    fi
}

# ------------------------------------------------------------
# Resolve KernelSU-Next Manager
# ------------------------------------------------------------

resolve_manager \
    "KSUN" \
    "$KSUN_REPO" \
    "$KSUN_WORKFLOW" \
    "$KSUN_BRANCH" \
    "$KSUN_SHA" \
    "manager" \
    "manager-spoofed" \
    "https://github.com/${KSUN_REPO}/actions"

# ------------------------------------------------------------
# Resolve SukiSU-Nova Manager
# ------------------------------------------------------------

resolve_manager \
    "SKSU" \
    "$SKSU_REPO" \
    "$SKSU_WORKFLOW" \
    "$SKSU_BRANCH" \
    "$SKSU_SHA" \
    "Manager" \
    "Manager-spoofed" \
    "https://github.com/${SKSU_REPO}/releases/latest"

# ------------------------------------------------------------
# Date and release configuration
# ------------------------------------------------------------

DATE_TAG=$(date +'%Y%m%d')

case "$WORKFLOW_TYPE" in

    compat)
        _tag_prefix="compat-"
        RELEASE_NAME="Seiran-GKI-Compat"
        ;;

    legacy)
        _tag_prefix="legacy-"
        RELEASE_NAME="Seiran-GKI-Legacy"
        ;;

    *)
        _tag_prefix=""
        RELEASE_NAME="Seiran-GKI"
        ;;

esac

# ------------------------------------------------------------
# Release tag
# ------------------------------------------------------------

case "$BUILD_TYPE" in

    testing)
        RELEASE_TAG="${_tag_prefix}${SUSFS_VERSION}-testing"
        IS_PRERELEASE="true"
        ;;

    stable)
        RELEASE_TAG="${_tag_prefix}${SUSFS_VERSION}"
        IS_PRERELEASE="false"
        ;;

    *)
        echo "[ERROR] Unsupported BUILD_TYPE: ${BUILD_TYPE}" >&2
        exit 1
        ;;

esac

ENCODED_TAG="${RELEASE_TAG//+/%2B}"

RELEASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${ENCODED_TAG}"

# ------------------------------------------------------------
# Export GitHub Actions environment
# ------------------------------------------------------------

if [ -n "${GITHUB_ENV:-}" ]; then

    {
        echo "BUILD_TYPE=$BUILD_TYPE"
        echo "WORKFLOW_TYPE=$WORKFLOW_TYPE"

        echo "KSUN_VERSION=$KSUN_VERSION"
        echo "SKSU_VERSION=$SKSU_VERSION"

        echo "KSUN_TAG=$KSUN_TAG"
        echo "SKSU_TAG=$SKSU_TAG"

        echo "KSUN_SHA=$KSUN_SHA"
        echo "SKSU_SHA=$SKSU_SHA"

        echo "KSUN_MANAGER_URL=$KSUN_MANAGER_URL"
        echo "SKSU_MANAGER_URL=$SKSU_MANAGER_URL"

        echo "KSUN_MANAGER_ARTIFACT_ID=$KSUN_MANAGER_ARTIFACT_ID"
        echo "KSUN_MANAGER_SPOOFED_ARTIFACT_ID=$KSUN_MANAGER_SPOOFED_ARTIFACT_ID"

        echo "SKSU_MANAGER_ARTIFACT_ID=$SKSU_MANAGER_ARTIFACT_ID"
        echo "SKSU_MANAGER_SPOOFED_ARTIFACT_ID=$SKSU_MANAGER_SPOOFED_ARTIFACT_ID"

        echo "KSUN_MANAGER_RUN_SHA=$KSUN_MANAGER_RUN_SHA"
        echo "SKSU_MANAGER_RUN_SHA=$SKSU_MANAGER_RUN_SHA"

        echo "KERNEL_VERSION=$KERNEL_VERSION"
        echo "KERNEL_UNAME=$KERNEL_UNAME"

        echo "KERNEL_VERSION_GKI=$KERNEL_VERSION_GKI"
        echo "KERNEL_UNAME_GKI=$KERNEL_UNAME_GKI"

        echo "SUSFS_VERSION=$SUSFS_VERSION"

        echo "DATE_TAG=$DATE_TAG"
        echo "RELEASE_TAG=$RELEASE_TAG"
        echo "RELEASE_NAME=$RELEASE_NAME"
        echo "IS_PRERELEASE=$IS_PRERELEASE"
        echo "RELEASE_URL=$RELEASE_URL"

        echo "SUSFS_MODULE_URL=https://github.com/sidex15/susfs4ksu-module/releases/latest"

    } >> "$GITHUB_ENV"

fi

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "                  VERSION RESOLUTION"
echo "============================================================"

if [ -n "$KERNEL_UNAME_GKI" ]; then
    echo "GKI Base       : $KERNEL_UNAME_GKI"
else
    echo "Kernel Version : $KERNEL_VERSION"
fi

echo "SUSFS          : $SUSFS_VERSION"

echo "KSU-Next Tag   : $KSUN_TAG"
echo "KSU-Next SHA   : ${KSUN_SHA:-unknown}"
echo "KSU-Next Manager: ${KSUN_MANAGER_ARTIFACT_ID:-unavailable}"

echo "SukiSU Tag     : $SKSU_TAG"
echo "SukiSU SHA     : ${SKSU_SHA:-unknown}"
echo "SukiSU Manager : ${SKSU_MANAGER_ARTIFACT_ID:-unavailable}"

echo "Build Type     : $BUILD_TYPE"
echo "Workflow Type  : $WORKFLOW_TYPE"

echo "Release Name   : $RELEASE_NAME"
echo "Release Tag    : $RELEASE_TAG"
echo "Prerelease     : $IS_PRERELEASE"
echo "Release URL    : $RELEASE_URL"

echo "============================================================"
echo "[OK] Versions resolved successfully."