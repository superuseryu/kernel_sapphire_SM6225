#!/usr/bin/env bash
# audit-logs.sh — collect per-job build logs into a zip
# env: GH_TOKEN / GITHUB_TOKEN, BUILD_TYPE, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_NUMBER, GITHUB_SHA
set -e

: "${GH_TOKEN:=${GITHUB_TOKEN:-}}"
export GH_TOKEN

: "${BUILD_TYPE:-stable}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_RUN_ID:?}"
: "${GITHUB_RUN_NUMBER:?}"

mkdir -p ./audit_logs

# Query all build jobs for this run (ignoring orchestration / release jobs and skipped jobs)
gh api --paginate "/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/jobs" \
  --jq '.jobs[] | select((.name | test("GKI|build|Kernel")) and (.name | test("Setup|Package|Release|Notify|matrix") | not) and .conclusion != "skipped") | [.id, .name] | @tsv' \
  > /tmp/build_jobs.tsv 2>/dev/null || true

# Strip BOM, ISO timestamp prefix, ANSI escape codes, CRLF, and GHA grouping markers
_clean_log() {
  sed '1s/^\xef\xbb\xbf//' \
  | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z //' \
  | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\(B//g; s/\r$//' \
  | sed '/^##\[group\]/d; /^##\[endgroup\]/d'
}

if [ -s /tmp/build_jobs.tsv ]; then
  while IFS=$'\t' read -r JOB_ID JOB_NAME; do
    [ -n "$JOB_ID" ] || continue
    # Extract variant part after " / " — e.g. "GKI-KSU-Next / GKI-KSU-Next" → "GKI-KSU-Next"
    SAFE=$(echo "$JOB_NAME" | sed 's|.* / ||' | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/__*/_/g; s/^_//; s/_$//')
    echo "[LOG] Fetching audit log for $JOB_NAME ($JOB_ID) -> ${SAFE}.log"
    gh api --allow-escape-sequences "/repos/${GITHUB_REPOSITORY}/actions/jobs/${JOB_ID}/logs" \
      2>/dev/null \
      | _clean_log \
      > "./audit_logs/${SAFE}.log" \
      || echo "[WARN] could not fetch: $JOB_NAME" > "./audit_logs/${SAFE}.log"
  done < /tmp/build_jobs.tsv
else
  echo "[WARN] No build jobs found to capture logs"
fi

cat > ./audit_logs/00_run_info.txt << RUNINFO
Run    : #${GITHUB_RUN_NUMBER}
Repo   : ${GITHUB_REPOSITORY}
SHA    : ${GITHUB_SHA:-unknown}
Date   : $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Type   : ${BUILD_TYPE}
URL    : https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
RUNINFO

[ "$BUILD_TYPE" = "testing" ] && SUFFIX="-testing" || SUFFIX=""
LOG_ZIP="build-audit-logs-$(date +'%Y-%m')${SUFFIX}.zip"

if [ -d ./audit_logs ] && [ "$(ls -A ./audit_logs 2>/dev/null)" ]; then
  zip -r9 "$LOG_ZIP" audit_logs/
  LOG_SIZE_MB=$(echo "scale=2; $(stat -c%s "$LOG_ZIP") / 1024 / 1024" | bc | sed 's/^\./0./')
  echo "LOG_AUDIT_ZIP=$LOG_ZIP"         >> "${GITHUB_ENV:-/dev/null}"
  echo "LOG_AUDIT_SIZE_MB=$LOG_SIZE_MB" >> "${GITHUB_ENV:-/dev/null}"
  echo "[OK] Audit log: $LOG_ZIP ($LOG_SIZE_MB MB)"
fi
