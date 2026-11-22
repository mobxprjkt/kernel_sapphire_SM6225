#!/usr/bin/env bash
# Telegram notifications for the SukiSU-Nova AIO build.
set -euo pipefail
MODE="${1:?usage: notify.sh <success|variant-failure|failure>}"
[ "${NOTIFY_ENABLED:-true}" = "true" ] || exit 0
: "${TELEGRAM_BOT_TOKEN:?}"
: "${TELEGRAM_CHAT_ID:?}"
_tg_msg() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    ${TELEGRAM_TOPIC_ID:+-d message_thread_id="$TELEGRAM_TOPIC_ID"} \
    -d text="$1" -d parse_mode="HTML" -d disable_web_page_preview=true >/dev/null
}
_tg_doc() {
  local file="$1" caption="$2"
  [ -f "$file" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    ${TELEGRAM_TOPIC_ID:+-F message_thread_id="$TELEGRAM_TOPIC_ID"} \
    -F document=@"$file" -F caption="$caption" >/dev/null
}
case "$MODE" in
  success)
    : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${START_TIME:?}" "${SHA:?}"
    duration=$(( $(date +%s) - START_TIME ))
    label=Stable; [ "${BUILD_TYPE:-stable}" = testing ] && label=Testing
    tag=$(printf '%s' "${RELEASE_TAG:-}" | sed 's/+/%2B/g')
    release="${RELEASE_URL:-https://github.com/${GITHUB_REPOSITORY}/releases}"
    compiler='AOSP Clang'; [ "${USE_CCACHE:-false}" = true ] && compiler='AOSP Clang + ccache'
    msg="<b>[${label}] Sapphiren SukiSU-Nova</b>%0ARun: #${RUN_NUMBER}%0ABranch: ${GITHUB_REF_NAME:-unknown}%0ACommit: ${SHA:0:8}%0ADuration: $((duration/60))m $((duration%60))s%0ATag: <code>${tag}</code>%0AManager: <code>${SKSU_TAG:-builtin}</code>%0ACompiler: ${compiler}%0A<a href='${release}'>Release</a> · <a href='${RUN_URL}'>Logs</a>"
    _tg_msg "$msg"
    for zip in ./release_zips/*.zip; do
      [ -f "$zip" ] || continue
      size=$(echo "scale=1; $(stat -c%s "$zip") / 1048576" | bc | sed 's/^\./0./')
      _tg_doc "$zip" "$(basename "$zip") — ${size} MB"
    done
    if [ -n "${LOG_AUDIT_ZIP:-}" ] && [ -f "$LOG_AUDIT_ZIP" ]; then
      _tg_doc "$LOG_AUDIT_ZIP" "Build audit logs"
    fi
    ;;
  variant-failure)
    : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${VARIANT:?}"
    _tg_msg "<b>Build failed — ${VARIANT}</b>%0ARun #${RUN_NUMBER} · <a href='${RUN_URL}'>Logs</a>"
    ;;
  failure)
    : "${RUN_URL:?}" "${RUN_NUMBER:?}"
    _tg_msg "<b>Build cancelled — Run #${RUN_NUMBER}</b>%0AStatus: ${BUILD_STATUS:-cancelled}%0A<a href='${RUN_URL}'>Logs</a>"
    ;;
  *) echo "Unknown notification mode: $MODE" >&2; exit 1 ;;
esac
