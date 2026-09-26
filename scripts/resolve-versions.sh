#!/usr/bin/env bash
# resolve-versions.sh — read version info from artifacts + GitHub API
# env: BUILD_TYPE, GITHUB_ENV (implicit)
set -e

: "${BUILD_TYPE:-stable}"

VERSION_FILE=$(find ./artifacts -name "kernel_version.txt" | head -1)
KERNEL_VERSION=$([ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "5.15.x")

UNAME_FILE=$(find ./artifacts -name "kernel_uname.txt" | head -1)
KERNEL_UNAME=$([ -f "$UNAME_FILE" ] && cat "$UNAME_FILE" || echo "$KERNEL_VERSION")

# GKI and CLO pin different upstream sublevels (see sources/source-pins.json), so an
# aio release (both sources bundled together) actually has two distinct kernel bases,
# not one. KERNEL_VERSION/KERNEL_UNAME above collapse to whichever artifact `find`
# happens to list first (alphabetically "clo-*" beats "gki-*"), which silently hid
# the GKI side. Resolve each source independently here so downstream scripts can show
# both. Artifact dirs are named "gki-<ksu>" / "clo-<ksu>" (see build-aio.yml matrix);
# GKI-Compat artifacts are "gkicompat-<ksu>", which doesn't match "gki-*", so on a
# compat build these two just come back empty and callers fall back to the single
# KERNEL_VERSION/KERNEL_UNAME above — no separate compat-specific branch needed.
GKI_VERSION_FILE=$(find ./artifacts -path "*gki-*" -name "kernel_version.txt" | head -1)
CLO_VERSION_FILE=$(find ./artifacts -path "*clo-*" -name "kernel_version.txt" | head -1)
GKI_UNAME_FILE=$(find ./artifacts -path "*gki-*" -name "kernel_uname.txt" | head -1)
CLO_UNAME_FILE=$(find ./artifacts -path "*clo-*" -name "kernel_uname.txt" | head -1)

KERNEL_VERSION_GKI=$([ -f "$GKI_VERSION_FILE" ] && cat "$GKI_VERSION_FILE" || echo "")
KERNEL_VERSION_CLO=$([ -f "$CLO_VERSION_FILE" ] && cat "$CLO_VERSION_FILE" || echo "")
KERNEL_UNAME_GKI=$([ -f "$GKI_UNAME_FILE" ] && cat "$GKI_UNAME_FILE" || echo "$KERNEL_VERSION_GKI")
KERNEL_UNAME_CLO=$([ -f "$CLO_UNAME_FILE" ] && cat "$CLO_UNAME_FILE" || echo "$KERNEL_VERSION_CLO")

# NOTE: pipeline exit code is from last cmd (tr), so jq failures are swallowed
# without pipefail. Use two-step fetch + explicit fallback instead.
_susfs_raw=$(curl -sf "https://api.github.com/repos/sidex15/susfs4ksu-module/tags" 2>/dev/null \
  | jq -r '.[0].name // empty' 2>/dev/null | tr -d ' \n')
SUSFS_VERSION="${_susfs_raw:-v1.5.2+_R27}"

_wf=$(find ./artifacts -name "ksun_tag.txt" | head -1)
KSUN_TAG=$([ -f "$_wf" ] && cat "$_wf" | tr -d '[:space:]' || echo "unknown")
_sf=$(find ./artifacts -name "rsku_tag.txt" | head -1)
RSKU_TAG=$([ -f "$_sf" ] && cat "$_sf" | tr -d '[:space:]' || echo "unknown")
# Version codes (for manager matching)
_kv=$(find ./artifacts -name "ksun_version.txt" | head -1)
KSUN_VERSION=$([ -f "$_kv" ] && cat "$_kv" | tr -d '[:space:]' || echo "")

_sv=$(find ./artifacts -name "rsku_version.txt" | head -1)
RSKU_VERSION=$([ -f "$_sv" ] && cat "$_sv" | tr -d '[:space:]' || echo "")

# Commit SHAs recorded at build time — used to match exact manager CI run
_ks=$(find ./artifacts -name "ksun_sha.txt" | head -1)
KSUN_SHA=$([ -f "$_ks" ] && cat "$_ks" | tr -d '[:space:]' || echo "")
_rs=$(find ./artifacts -name "rsku_sha.txt" | head -1)
RSKU_SHA=$([ -f "$_rs" ] && cat "$_rs" | tr -d '[:space:]' || echo "")

# Find manager CI run whose head_sha matches the kernel driver SHA recorded at build time.
# Falls back to latest successful run if no SHA match found (e.g. testing build or old artifact).
_ksun_find_run() {
  local sha="$1" page run_id
  for page in 1 2 3; do
    local runs
    runs=$(curl -sf --max-time 15 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/actions/workflows/build-manager-ci.yml/runs?status=success&branch=dev&per_page=20&page=${page}")
    run_id=$(echo "$runs" | python3 -c "
import sys,json
d=json.load(sys.stdin)
sha=sys.argv[1] if len(sys.argv)>1 else ""
for r in d.get("workflow_runs",[]):
    if r["head_sha"]==sha:
        print(r["id"]); break
" "$sha" 2>/dev/null | tr -d "[:space:]")
    [ -n "$run_id" ] && { echo "$run_id"; return 0; }
    # Stop paging if no more runs
    local count
    count=$(echo "$runs" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("workflow_runs",[])))') 2>/dev/null
    [ "${count:-0}" -lt 20 ] && break
  done
  # Fallback: latest run
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/actions/workflows/build-manager-ci.yml/runs?status=success&branch=dev&per_page=1" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["workflow_runs"][0]["id"] if d["workflow_runs"] else "")' 2>/dev/null | tr -d "[:space:]"
}
_kr=$(_ksun_find_run "$KSUN_SHA")
KSUN_MANAGER_URL="${_kr:+https://github.com/KernelSU-Next/KernelSU-Next/actions/runs/${_kr}}"
KSUN_MANAGER_URL="${KSUN_MANAGER_URL:-https://github.com/KernelSU-Next/KernelSU-Next/actions}"
KSUN_MANAGER_ARTIFACT_ID=$([ -n "$_kr" ] && \
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/actions/runs/${_kr}/artifacts" \
  | jq -r '.artifacts[] | select(.name == "manager") | .id // empty' | head -1 || true)
  
KSUN_MANAGER_SPOOFED_ARTIFACT_ID=$([ -n "$_kr" ] && \
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/actions/runs/${_kr}/artifacts" \
  | jq -r '.artifacts[] | select(.name == "manager-spoofed") | .id // empty' | head -1 || true)  

_rsku_find_run() {
  local sha="$1" page run_id
  for page in 1 2 3; do
    local runs
    runs=$(curl -sf --max-time 15 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/ReSukiSU/ReSukiSU/actions/workflows/build-manager.yml/runs?status=success&branch=main&per_page=20&page=${page}")
    run_id=$(echo "$runs" | python3 -c "
import sys,json
d=json.load(sys.stdin)
sha=sys.argv[1] if len(sys.argv)>1 else ""
for r in d.get("workflow_runs",[]):
    if r["head_sha"]==sha:
        print(r["id"]); break
" "$sha" 2>/dev/null | tr -d "[:space:]")
    [ -n "$run_id" ] && { echo "$run_id"; return 0; }
    local count
    count=$(echo "$runs" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("workflow_runs",[])))') 2>/dev/null
    [ "${count:-0}" -lt 20 ] && break
  done
  # Fallback: latest run
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/ReSukiSU/ReSukiSU/actions/workflows/build-manager.yml/runs?status=success&branch=main&per_page=1" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["workflow_runs"][0]["id"] if d["workflow_runs"] else "")' 2>/dev/null | tr -d "[:space:]"
}
_sr=$(_rsku_find_run "$RSKU_SHA")
RSKU_MANAGER_URL="${_sr:+https://github.com/ReSukiSU/ReSukiSU/actions/runs/${_sr}}"
RSKU_MANAGER_URL="${RSKU_MANAGER_URL:-https://github.com/ReSukiSU/ReSukiSU/actions/workflows/build-manager.yml}"
RSKU_MANAGER_ARTIFACT_ID=$([ -n "$_sr" ] && \
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/ReSukiSU/ReSukiSU/actions/runs/${_sr}/artifacts" \
  | jq -r '.artifacts[] | select(.name == "Manager-release") | select(.expired == false) | .id // empty' | head -1 || true)

RSKU_MANAGER_SPOOFED_ARTIFACT_ID=$([ -n "$_sr" ] && \
  curl -sf --max-time 10 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/ReSukiSU/ReSukiSU/actions/runs/${_sr}/artifacts" \
  | jq -r '.artifacts[] | select(.name == "Spoofed-Manager-release") | select(.expired == false) | .id // empty' | head -1 || true)

DATE_TAG=$(date +'%Y%m%d')

: "${WORKFLOW_TYPE:-aio}"

if [ "$WORKFLOW_TYPE" = "compat" ]; then
  _tag_prefix="compat-"
  RELEASE_NAME="Seiran-GKI-Compat"
else
  _tag_prefix=""
  RELEASE_NAME="Seiran-GKI"
fi

if [ "$BUILD_TYPE" = "testing" ]; then
  RELEASE_TAG="${_tag_prefix}${SUSFS_VERSION}-testing"
  IS_PRERELEASE="true"
else
  RELEASE_TAG="${_tag_prefix}${SUSFS_VERSION}"
  IS_PRERELEASE="false"
fi

ENCODED_TAG=$(echo "$RELEASE_TAG" | sed 's/+/%2B/g')
RELEASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${ENCODED_TAG}"

{
  echo "KSUN_VERSION=$KSUN_VERSION"
  echo "RSKU_VERSION=$RSKU_VERSION"
  echo "KSUN_MANAGER_URL=$KSUN_MANAGER_URL"
  echo "RSKU_MANAGER_URL=$RSKU_MANAGER_URL"
  echo "KSUN_MANAGER_ARTIFACT_ID=$KSUN_MANAGER_ARTIFACT_ID"
  echo "KSUN_MANAGER_SPOOFED_ARTIFACT_ID=$KSUN_MANAGER_SPOOFED_ARTIFACT_ID"
  echo "RSKU_MANAGER_ARTIFACT_ID=$RSKU_MANAGER_ARTIFACT_ID"
  echo "RSKU_MANAGER_SPOOFED_ARTIFACT_ID=$RSKU_MANAGER_SPOOFED_ARTIFACT_ID"
  echo "KERNEL_VERSION=$KERNEL_VERSION"
  echo "KERNEL_UNAME=$KERNEL_UNAME"
  echo "KERNEL_VERSION_GKI=$KERNEL_VERSION_GKI"
  echo "KERNEL_VERSION_CLO=$KERNEL_VERSION_CLO"
  echo "KERNEL_UNAME_GKI=$KERNEL_UNAME_GKI"
  echo "KERNEL_UNAME_CLO=$KERNEL_UNAME_CLO"
  echo "SUSFS_VERSION=$SUSFS_VERSION"
  echo "KSUN_TAG=$KSUN_TAG"
  echo "RSKU_TAG=$RSKU_TAG"
  echo "DATE_TAG=$DATE_TAG"
  echo "RELEASE_TAG=$RELEASE_TAG"
  echo "RELEASE_NAME=$RELEASE_NAME"
  echo "IS_PRERELEASE=$IS_PRERELEASE"
  echo "RELEASE_URL=$RELEASE_URL"
  echo "SUSFS_MODULE_URL=https://github.com/sidex15/susfs4ksu-module/releases/latest"
} >> "${GITHUB_ENV:-/dev/null}"

echo "[OK] Versions resolved"
if [ -n "$KERNEL_UNAME_GKI" ] && [ -n "$KERNEL_UNAME_CLO" ]; then
  echo "  GKI base: $KERNEL_UNAME_GKI"
  echo "  CLO base: $KERNEL_UNAME_CLO"
else
  echo "  Kernel  : $KERNEL_VERSION"
fi
echo "  SUSFS   : $SUSFS_VERSION"
echo "  KSU-Next: $KSUN_TAG"
echo "  ReSukiSU: $RSKU_TAG"
echo "  Tag     : $RELEASE_TAG"
