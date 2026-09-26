#!/usr/bin/env bash
# notify.sh — Telegram notification dispatcher
# Usage: notify.sh <success|variant-failure|failure|check>
# Required env: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
# Optional env: TELEGRAM_TOPIC_ID (thread/topic ID for group topics)

set -euo pipefail

MODE="${1:?usage: notify.sh <success|variant-failure|failure|check>}"

: "${TELEGRAM_BOT_TOKEN:?}"
: "${TELEGRAM_CHAT_ID:?}"

_tg_msg() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    ${TELEGRAM_TOPIC_ID:+-d message_thread_id="$TELEGRAM_TOPIC_ID"} \
    -d text="$1" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true \
    > /dev/null
}

_tg_doc() {
  local FILE="$1" CAPTION="$2"
  [ -f "$FILE" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    ${TELEGRAM_TOPIC_ID:+-F message_thread_id="$TELEGRAM_TOPIC_ID"} \
    -F document=@"$FILE" \
    -F caption="$CAPTION" \
    > /dev/null
}

# ---------------------------------------------------------------------------
# success — called from release.yml after a full aio build + release
# ---------------------------------------------------------------------------
if [ "$MODE" = "success" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${START_TIME:?}" "${SHA:?}"

  SHORT_SHA="${SHA:0:8}"
  COMMIT_MSG=$(git log -1 --format=%s 2>/dev/null || echo "")
  DURATION=$(( $(date +%s) - START_TIME ))
  DATE_STR=$(date -u +'%Y-%m-%d')

  BUILD_LABEL="Stable"
  [ "${BUILD_TYPE:-stable}" = "testing" ] && BUILD_LABEL="Testing"

  # URL-encode + in tag (form-encoding turns it into space otherwise)
  DISPLAY_TAG=$(printf '%s' "${RELEASE_TAG:-}" | sed 's/+/%2B/g')
  DISPLAY_SUSFS=$(printf '%s' "${SUSFS_VERSION:-}" | sed 's/+/%2B/g')

  RELEASE_LINK="${RELEASE_URL:-https://github.com/${GITHUB_REPOSITORY}/releases}"

  # Commit line — message if non-empty, else just the hash
  if [ -n "$COMMIT_MSG" ]; then
    COMMIT_LINE="<a href='https://github.com/${GITHUB_REPOSITORY}/commit/${SHA}'>${SHORT_SHA}</a> — ${COMMIT_MSG}"
  else
    COMMIT_LINE="<a href='https://github.com/${GITHUB_REPOSITORY}/commit/${SHA}'>${SHORT_SHA}</a>"
  fi

  # Branch + actor
  BRANCH_LINE="${GITHUB_REF_NAME:-unknown} · ${GITHUB_ACTOR:-yurika-sudo}"

  MSG="<b>[${BUILD_LABEL}] Seiran Kernel</b>%0A%0A"
  MSG="${MSG}Run: #${RUN_NUMBER}%0A"
  MSG="${MSG}Branch: ${GITHUB_REF_NAME:-unknown}%0A"
  MSG="${MSG}Actor: ${GITHUB_ACTOR:-yurika-sudo}%0A"
  MSG="${MSG}Commit: <a href='https://github.com/${GITHUB_REPOSITORY}/commit/${SHA}'>${SHORT_SHA}</a>%0A"
  [ -n "$COMMIT_MSG" ] && MSG="${MSG}Message: ${COMMIT_MSG}%0A"
  MSG="${MSG}%0A"
  MSG="${MSG}Duration: $((DURATION/60))m $((DURATION%60))s%0A"
  MSG="${MSG}Date: ${DATE_STR}%0A"
  MSG="${MSG}Tag: <code>${DISPLAY_TAG}</code>%0A"
  MSG="${MSG}%0A"
  MSG="${MSG}KSU-Next: <code>${KSUN_TAG:-unknown}</code>%0A"
  MSG="${MSG}ReSukiSU: <code>${RSKU_TAG:-unknown}</code>%0A"
  MSG="${MSG}SUSFS: <code>${DISPLAY_SUSFS}</code>%0A"
  MSG="${MSG}%0A"
  MSG="${MSG}<a href='${RELEASE_LINK}'>Release</a>%0A"
  MSG="${MSG}<a href='${RUN_URL}'>Logs</a>"

  _tg_msg "$MSG"

  # Attach per-variant ZIPs
  for ZIP in ./release_zips/*.zip; do
    [ -f "$ZIP" ] || continue
    SIZE_MB=$(echo "scale=1; $(stat -c%s "$ZIP") / 1048576" | bc | sed 's/^\./0./')
    _tg_doc "$ZIP" "$(basename "$ZIP") — ${SIZE_MB} MB"
  done

# ---------------------------------------------------------------------------
# variant-failure — called from build-kernel.yml when a single variant fails
# ---------------------------------------------------------------------------
elif [ "$MODE" = "variant-failure" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${VARIANT:?}"

  BUILD_LABEL="Stable"
  [ "${BUILD_TYPE:-stable}" = "testing" ] && BUILD_LABEL="Testing"

  MSG="<b>[${BUILD_LABEL}] Build failed — ${VARIANT}</b>%0A%0A"
  MSG="${MSG}Run #${RUN_NUMBER} · <a href='${RUN_URL}'>Logs</a>"

  _tg_msg "$MSG"

# ---------------------------------------------------------------------------
# failure — called from build-aio.yml notify-failure job (cancelled run)
# ---------------------------------------------------------------------------
elif [ "$MODE" = "failure" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}"

  BUILD_LABEL="Stable"
  [ "${BUILD_TYPE:-stable}" = "testing" ] && BUILD_LABEL="Testing"

  MSG="<b>[${BUILD_LABEL}] Build cancelled — Run #${RUN_NUMBER}</b>%0A%0A"
  MSG="${MSG}Status: ${BUILD_STATUS:-cancelled}%0A"
  MSG="${MSG}<a href='${RUN_URL}'>Logs</a>"

  _tg_msg "$MSG"

# ---------------------------------------------------------------------------
# check — called from check-updates.yml notify job
# ---------------------------------------------------------------------------
elif [ "$MODE" = "check" ]; then
  : "${RUN_URL:?}"

  if [ "${CHECK_FAILED:-false}" = "true" ]; then
    MSG="<b>[check-updates] Version fetch failed</b>%0A%0A"
    MSG="${MSG}<a href='${RUN_URL}'>Logs</a>"
    _tg_msg "$MSG"
    exit 0
  fi

  if [ "${HAS_UPDATE:-false}" != "true" ]; then
    MSG="<b>[check-updates] No upstream changes</b>%0A%0A"
    MSG="${MSG}KSU-Next <code>${CHECK_KSUN_TAG:-?}</code> · ReSukiSU <code>${CHECK_RSKU_TAG:-?}</code> · SUSFS <code>${CHECK_SUSFS_TAG:-?}</code>%0A"
    MSG="${MSG}GKI <code>${CHECK_GKI_SUB:-?}</code> · CLO <code>${CHECK_CLO_SUB:-?}</code>%0A%0A"
    MSG="${MSG}<a href='${RUN_URL}'>Logs</a>"
    _tg_msg "$MSG"
    exit 0
  fi

  # Has update
  MSG="<b>[check-updates] Upstream update detected</b>%0A%0A"
  [ -n "${UPDATE_DETAIL:-}" ] && MSG="${MSG}${UPDATE_DETAIL}%0A%0A"
  MSG="${MSG}KSU-Next <code>${CHECK_KSUN_TAG:-?}</code> · ReSukiSU <code>${CHECK_RSKU_TAG:-?}</code> · SUSFS <code>${CHECK_SUSFS_TAG:-?}</code>%0A"
  MSG="${MSG}GKI <code>${CHECK_GKI_SUB:-?}</code> · CLO <code>${CHECK_CLO_SUB:-?}</code>%0A"

  if [ -n "${HELD_BACK:-}" ]; then
    MSG="${MSG}%0AHeld back (gate failed):%0A"
    while IFS= read -r line; do
      [ -n "$line" ] && MSG="${MSG}  ${line}%0A"
    done <<< "$HELD_BACK"
  fi

  MSG="${MSG}%0A<a href='${RUN_URL}'>Logs</a>"
  _tg_msg "$MSG"

else
  echo "notify.sh: unknown mode '$MODE'" >&2
  exit 1
fi
