#!/usr/bin/env bash
# check-sources.sh — fetch latest upstream versions and compare against source-pins.json
set -e

PINS_FILE="sources/source-pins.json"

# Safe curl wrapper — never fails the script
_curl() { curl -s --retry 3 --retry-delay 2 "$@" || echo ""; }

# Read a value from source-pins.json
_pin() { jq -r ".${1} // \"unknown\"" "$PINS_FILE" 2>/dev/null || echo "unknown"; }

echo "=== Fetching upstream sources ==="

KSUN_TAG=$(_curl "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/tags" \
  | jq -r '.[0].name // "unknown"' 2>/dev/null || echo "unknown")
[ -z "$KSUN_TAG" ] && KSUN_TAG="unknown"
echo "KSU-Next     : $KSUN_TAG"

SUKI_TAG=$(_curl "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/latest" \
  | jq -r '.tag_name // "unknown"' 2>/dev/null || echo "unknown")
[ -z "$SUKI_TAG" ] && SUKI_TAG="unknown"
echo "SukiSU-Ultra : $SUKI_TAG"

SUSFS_TAG=$(_curl "https://api.github.com/repos/sidex15/susfs4ksu-module/tags" \
  | jq -r 'if type=="array" and length>0 then .[0].name else "unknown" end' 2>/dev/null \
  || echo "unknown")
[ -z "$SUSFS_TAG" ] && SUSFS_TAG="unknown"
echo "SUSFS module : $SUSFS_TAG"

GKI_RAW=$(_curl \
  "https://android.googlesource.com/kernel/common/+/refs/heads/android13-5.15-lts/Makefile?format=TEXT")
GKI_MK=$(echo "$GKI_RAW" | base64 -d 2>/dev/null || true)
GKI_SUB=$(echo "$GKI_MK" | awk -F' *= *' \
  '/^VERSION /    {v=$2}
   /^PATCHLEVEL / {p=$2}
   /^SUBLEVEL /   {s=$2}
   END { if(v && p && s) print "v"v"."p"."s; else print "unknown" }')
GKI_SUB="${GKI_SUB:-unknown}"
echo "GKI 5.15     : $GKI_SUB"

CLO_RAW=$(_curl \
  "https://git.codelinaro.org/clo/la/kernel/msm-5.15/-/raw/kernel.lnx.5.15.r1-rel/Makefile")
CLO_SUB=$(echo "$CLO_RAW" | awk -F' *= *' \
  '/^VERSION /    {v=$2}
   /^PATCHLEVEL / {p=$2}
   /^SUBLEVEL /   {s=$2}
   END { if(v && p && s) print "v"v"."p"."s; else print "unknown" }')
CLO_SUB="${CLO_SUB:-unknown}"
echo "CLO 5.15     : $CLO_SUB"

echo ""
echo "=== Comparing against source-pins.json ==="

PIN_GKI=$(_pin "gki_sublevel")
PIN_CLO=$(_pin "clo_sublevel")
PIN_KSUN=$(_pin "ksun_tag")
PIN_SUKI=$(_pin "suki_tag")
PIN_SUSFS=$(_pin "susfs_tag")

UPDATES=()
FAILED=()

# A fetch that failed reports the literal string "unknown" (see _curl/awk fallbacks
# above) — that's a signal this run couldn't reach upstream, not a real version.
# Comparing it against the pin as if it were a legitimate value caused false
# "update available" notifications, and — since the workflow unconditionally commits
# CHECK_<X> whenever HAS_UPDATE=true — could push "unknown" into source-pins.json for
# real on a bad run. On failure, keep the last known-good pin and report the failure
# separately instead, so it's visible without being treated as an update.
if [ "$GKI_SUB" = "unknown" ]; then
  FAILED+=("GKI"); GKI_SUB="$PIN_GKI"
elif [ "$GKI_SUB" != "$PIN_GKI" ]; then
  UPDATES+=("GKI: ${PIN_GKI} → ${GKI_SUB}")
fi

if [ "$CLO_SUB" = "unknown" ]; then
  FAILED+=("CLO"); CLO_SUB="$PIN_CLO"
elif [ "$CLO_SUB" != "$PIN_CLO" ]; then
  UPDATES+=("CLO: ${PIN_CLO} → ${CLO_SUB}")
fi

KSUN_CHANGED="false"
SUKI_CHANGED="false"

if [ "$KSUN_TAG" = "unknown" ]; then
  FAILED+=("KSU-Next"); KSUN_TAG="$PIN_KSUN"
elif [ "$KSUN_TAG" != "$PIN_KSUN" ]; then
  UPDATES+=("KSU-Next: ${PIN_KSUN} → ${KSUN_TAG}")
  KSUN_CHANGED="true"
fi

if [ "$SUKI_TAG" = "unknown" ]; then
  FAILED+=("SukiSU"); SUKI_TAG="$PIN_SUKI"
elif [ "$SUKI_TAG" != "$PIN_SUKI" ]; then
  UPDATES+=("SukiSU: ${PIN_SUKI} → ${SUKI_TAG}")
  SUKI_CHANGED="true"
fi

if [ "$SUSFS_TAG" = "unknown" ]; then
  FAILED+=("SUSFS"); SUSFS_TAG="$PIN_SUSFS"
elif [ "$SUSFS_TAG" != "$PIN_SUSFS" ]; then
  UPDATES+=("SUSFS: ${PIN_SUSFS} → ${SUSFS_TAG}")
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "[WARN] Could not fetch (kept last known-good pin): ${FAILED[*]}"
fi
FAILED_DETAIL=$(printf '%s\n' "${FAILED[@]}")

if [ ${#UPDATES[@]} -gt 0 ]; then
  echo "Updates detected:"
  for U in "${UPDATES[@]}"; do echo "  • $U"; done
  HAS_UPDATE="true"
  UPDATE_DETAIL=$(printf '%s\n' "${UPDATES[@]}")
else
  echo "All sources up to date."
  HAS_UPDATE="false"
  UPDATE_DETAIL=""
fi

# Job-level outputs — consumed cross-job by check-updates.yml (verify gate +
# apply-pins). Multi-line values use the same <<EOF heredoc syntax GITHUB_ENV
# uses; GITHUB_OUTPUT supports it identically.
{
  echo "ksun_tag=$KSUN_TAG"
  echo "suki_tag=$SUKI_TAG"
  echo "susfs_tag=$SUSFS_TAG"
  echo "gki_sub=$GKI_SUB"
  echo "clo_sub=$CLO_SUB"
  echo "has_update=$HAS_UPDATE"
  echo "ksun_changed=$KSUN_CHANGED"
  echo "suki_changed=$SUKI_CHANGED"
  echo "update_detail<<EOF"
  echo "$UPDATE_DETAIL"
  echo "EOF"
  echo "check_failed<<EOF"
  echo "$FAILED_DETAIL"
  echo "EOF"
} >> "${GITHUB_OUTPUT:-/dev/null}"

echo "=== Done ==="
