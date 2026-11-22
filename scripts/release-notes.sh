#!/usr/bin/env bash
set -e
: "${BUILD_TYPE:-stable}"
: "${RUN_URL:?}"
: "${REPO:?}"
: "${SHA:?}"
SHORT_SHA="${SHA:0:9}"
COMMIT_URL="https://github.com/${REPO}/commit/${SHA}"
BODY=""
if [ "$BUILD_TYPE" = "testing" ]; then
  BODY+=$'> [!WARNING]\n> Testing build. Use at your own risk.\n\n'
fi
BODY+="**Kernel:** Sapphiren / SukiSU-Nova"$'\n'
BODY+="**SukiSU-Nova:** [${SKSU_TAG:-builtin}](${SKSU_MANAGER_URL:-https://github.com/SukiSU-Nova/SukiSU-Nova/releases/latest})"$'\n'
BODY+="**Manager APK:** attached when an upstream CI artifact is available"$'\n'
BODY+="**Target:** Redmi Note 13 4G / NFC (sapphire, sapphiren) — A/B"$'\n'
BODY+="**Compiler:** AOSP Clang"$'\n\n'
BODY+=$'> [!IMPORTANT]\n> Install the matching SukiSU-Nova Manager build for the kernel version.\n\n'
BODY+="**Commit:** [\`${SHORT_SHA}\`](${COMMIT_URL})"$'\n'
BODY+="**Build logs:** [GitHub Actions run](${RUN_URL})"
{
  echo "RELEASE_BODY<<EOREL"
  echo "$BODY"
  echo "EOREL"
} >> "${GITHUB_ENV:-/dev/null}"
