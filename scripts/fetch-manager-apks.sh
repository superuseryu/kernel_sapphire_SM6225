#!/usr/bin/env bash
# fetch-manager-apks.sh — pull manager APK from upstream CI artifact, attach to release
# env: GITHUB_TOKEN, KSUN_MANAGER_ARTIFACT_ID, KSUN_MANAGER_SPOOFED_ARTIFACT_ID, SUKI_MANAGER_ARTIFACT_ID
set -e

mkdir -p ./manager_apks

_fetch() {
  local repo="$1" artifact_id="$2" label="$3"
  if [ -z "$artifact_id" ]; then
    echo "[SKIP] No artifact ID for $label"
    return 0
  fi

  local tmp="/tmp/mgr_${label}"
  mkdir -p "$tmp"

  local attempt ok=0
  for attempt in 1 2 3; do
    if curl -sfL --max-time 60 --location \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repo}/actions/artifacts/${artifact_id}/zip" \
      -o "${tmp}/artifact.zip"; then
      ok=1
      break
    fi
    echo "[WARN] Fetch attempt ${attempt}/3 failed for $label — retrying in 5s"
    sleep 5
  done
  if [ "$ok" -ne 1 ]; then
    echo "[WARN] Fetch failed for $label after 3 attempts — skipping"
    return 0
  fi

  unzip -j "${tmp}/artifact.zip" "*.apk" -d "${tmp}/" 2>/dev/null \
    || { echo "[WARN] No APK in $label artifact — skipping"; return 0; }

  local apk
  # Prefer arm64-v8a; fall back to universal; last resort: whatever find gives first.
  # ReSukiSU artifact ships 4 ABIs — without this filter head -1 may pick x86_64.
  apk=$(find "${tmp}" -name "*arm64-v8a*.apk" | head -1)
  [ -z "$apk" ] && apk=$(find "${tmp}" -name "*universal*.apk" | head -1)
  [ -z "$apk" ] && apk=$(find "${tmp}" -name "*.apk" | head -1)
  [ -z "$apk" ] && { echo "[WARN] APK not found post-extract for $label"; return 0; }

  local apk_name
  apk_name=$(basename "$apk")

  # ReSukiSU's manager artifact ships with a bare "Manager.apk" /
  # "Spoofed-Manager.apk" — no version/commit baked in like KSUN's does.
  # Prefix so it's identifiable in the release asset list at a glance.
  case "$(echo "$apk_name" | tr '[:upper:]' '[:lower:]')" in
    manager.apk)
      _ver="${RSKU_VERSION:-}"
      apk_name="ReSukiSU-Manager${_ver:+-${_ver}}.apk"
      ;;
    spoofed-manager.apk)
      _ver="${RSKU_VERSION:-}"
      apk_name="ReSukiSU-Spoofed-Manager${_ver:+-${_ver}}.apk"
      ;;
  esac

  # ReSukiSU ships identical filenames in both Manager-release and
  # Spoofed-Manager-release artifacts (e.g. both contain arm64-v8a-release.apk).
  # Disambiguate by prefixing spoofed labels so collision guard never fires.
  case "$label" in
    *-spoofed)
      case "$(echo "$apk_name" | tr '[:upper:]' '[:lower:]')" in
        resukisu_*-release.apk) apk_name="${apk_name/-release.apk/-spoofed-release.apk}" ;;
        resukisu_*-debug.apk)   apk_name="${apk_name/-debug.apk/-spoofed-debug.apk}" ;;
        *)                      apk_name="Spoofed-${apk_name}" ;;
      esac
      ;;
  esac

  # Keep upstream's own Gradle-generated filename (e.g.
  # KernelSU_Next_v3.3.0_33214-release.apk) instead of inventing ours.
  local dest="./manager_apks/${apk_name}"
  if [ -e "$dest" ]; then
    echo "[WARN] Filename collision for $label: $(basename "$apk") already fetched — skipping to avoid overwrite."
    return 0
  fi

  cp "$apk" "$dest"
  echo "[OK] $(basename "$apk") ($(du -h "$dest" | cut -f1))"
}

_fetch "KernelSU-Next/KernelSU-Next" "${KSUN_MANAGER_ARTIFACT_ID:-}"         "ksun"
_fetch "KernelSU-Next/KernelSU-Next" "${KSUN_MANAGER_SPOOFED_ARTIFACT_ID:-}" "ksun-spoofed"
_fetch "ReSukiSU/ReSukiSU"   "${RSKU_MANAGER_ARTIFACT_ID:-}"         "rsku"
_fetch "ReSukiSU/ReSukiSU"   "${RSKU_MANAGER_SPOOFED_ARTIFACT_ID:-}" "rsku-spoofed"
