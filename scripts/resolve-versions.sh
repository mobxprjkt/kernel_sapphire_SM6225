#!/usr/bin/env bash
# Resolve the single SukiSU-Nova build and its matching upstream manager artifact.
set -e
: "${BUILD_TYPE:-stable}"
VERSION_FILE=$(find ./artifacts -name 'kernel_version.txt' | head -1)
KERNEL_VERSION=$([ -f "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" || echo '5.15.x')
UNAME_FILE=$(find ./artifacts -name 'kernel_uname.txt' | head -1)
KERNEL_UNAME=$([ -f "$UNAME_FILE" ] && tr -d '[:space:]' < "$UNAME_FILE" || echo "$KERNEL_VERSION")
_sf=$(find ./artifacts -name 'sksu_tag.txt' | head -1)
SKSU_TAG=$([ -f "$_sf" ] && tr -d '[:space:]' < "$_sf" || echo 'builtin')
_sv=$(find ./artifacts -name 'sksu_version.txt' | head -1)
SKSU_VERSION=$([ -f "$_sv" ] && tr -d '[:space:]' < "$_sv" || echo '')
_ss=$(find ./artifacts -name 'sksu_sha.txt' | head -1)
SKSU_SHA=$([ -f "$_ss" ] && tr -d '[:space:]' < "$_ss" || echo '')

# Prefer the manager artifact built from the same SukiSU-Nova commit; otherwise latest successful main run.
_sr=''
if [ -n "$SKSU_SHA" ]; then
  _sr=$(curl -sf --max-time 15 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/SukiSU-Nova/SukiSU-Nova/actions/workflows/build-manager.yml/runs?head_sha=${SKSU_SHA}&status=success&per_page=1" \
    | jq -r '.workflow_runs[0].id // empty' 2>/dev/null || true)
fi
if [ -z "$_sr" ]; then
  _sr=$(curl -sf --max-time 15 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    'https://api.github.com/repos/SukiSU-Nova/SukiSU-Nova/actions/workflows/build-manager.yml/runs?status=success&branch=main&per_page=1' \
    | jq -r '.workflow_runs[0].id // empty' 2>/dev/null || true)
fi
SKSU_MANAGER_URL="${_sr:+https://github.com/SukiSU-Nova/SukiSU-Nova/actions/runs/${_sr}}"
SKSU_MANAGER_URL="${SKSU_MANAGER_URL:-https://github.com/SukiSU-Nova/SukiSU-Nova/releases/latest}"
SKSU_MANAGER_ARTIFACT_ID=''
SKSU_MANAGER_SPOOFED_ARTIFACT_ID=''
if [ -n "$_sr" ]; then
  _artifacts=$(curl -sf --max-time 15 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/SukiSU-Nova/SukiSU-Nova/actions/runs/${_sr}/artifacts" || echo '{}')
  SKSU_MANAGER_ARTIFACT_ID=$(echo "$_artifacts" | jq -r '.artifacts[] | select(.name == "Manager" and .expired == false) | .id' | head -1)
  SKSU_MANAGER_SPOOFED_ARTIFACT_ID=$(echo "$_artifacts" | jq -r '.artifacts[] | select(.name == "Manager-spoofed" and .expired == false) | .id' | head -1)
fi
DATE_TAG=$(date +'%Y%m%d')
RELEASE_NAME='Sapphiren-SukiSU-Nova'
_tag_prefix=''
if [ "$BUILD_TYPE" = 'testing' ]; then
  RELEASE_TAG="sksu-${SKSU_VERSION:-${SKSU_TAG}}-testing"
  IS_PRERELEASE='true'
else
  RELEASE_TAG="sksu-${SKSU_VERSION:-${SKSU_TAG}}"
  IS_PRERELEASE='false'
fi
ENCODED_TAG=$(echo "$RELEASE_TAG" | sed 's/+/%2B/g')
RELEASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${ENCODED_TAG}"
{
  echo "SKSU_VERSION=$SKSU_VERSION"
  echo "SKSU_MANAGER_URL=$SKSU_MANAGER_URL"
  echo "SKSU_MANAGER_ARTIFACT_ID=$SKSU_MANAGER_ARTIFACT_ID"
  echo "SKSU_MANAGER_SPOOFED_ARTIFACT_ID=$SKSU_MANAGER_SPOOFED_ARTIFACT_ID"
  echo "KERNEL_VERSION=$KERNEL_VERSION"
  echo "KERNEL_UNAME=$KERNEL_UNAME"
  echo "SKSU_TAG=$SKSU_TAG"
  echo "DATE_TAG=$DATE_TAG"
  echo "RELEASE_TAG=$RELEASE_TAG"
  echo "RELEASE_NAME=$RELEASE_NAME"
  echo "IS_PRERELEASE=$IS_PRERELEASE"
  echo "RELEASE_URL=$RELEASE_URL"
} >> "${GITHUB_ENV:-/dev/null}"
echo "[OK] SukiSU-Nova: $SKSU_TAG | Kernel: $KERNEL_UNAME | Release: $RELEASE_TAG"
