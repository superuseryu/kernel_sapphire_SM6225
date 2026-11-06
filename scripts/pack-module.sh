#!/usr/bin/env bash
# pack-module.sh — build a per-variant KSU/Magisk module zip carrying
# zram.ko + zsmalloc.ko + runtime tweaks (NAP cpuidle, ADIOS I/O, Reflex
# cpufreq), so the full seiran_core feature set reaches the device
# (CONFIG_ZRAM=m means it never ships via the Image-only AnyKernel3 zip).
#
# env: SOURCE_TYPE (e.g. gki-ksun), WORK_DIR, TEMPLATE_DIR (defaults to
# scripts/module_template relative to this script), OUT_ZIP (optional)
set -e

: "${SOURCE_TYPE:?}"
: "${WORK_DIR:?}"
: "${COMMIT_SHA:=unknown}"
: "${BUILD_NUM:=0}"
SHORT_SHA="${COMMIT_SHA:0:8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-$SCRIPT_DIR/module_template}"
KO_DIR="${WORK_DIR}/out/dist/ko"
STAGE_DIR="${WORK_DIR}/out/seiran-core"
OUT_ZIP="${OUT_ZIP:-${WORK_DIR}/out/seiran-core.zip}"

if [ ! -f "${KO_DIR}/zram.ko" ] || [ ! -f "${KO_DIR}/zsmalloc.ko" ]; then
  echo "[SKIP] ${SOURCE_TYPE}: zram.ko/zsmalloc.ko not found in ${KO_DIR} — did build.sh's modules step run and succeed?"
  exit 0
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/module"

# Copy template, substituting @VARIANT@ with the actual variant name.
cp -r "$TEMPLATE_DIR"/. "$STAGE_DIR"/
mv "$STAGE_DIR/module.prop.template" "$STAGE_DIR/module.prop"
sed -i "s/@VARIANT@/${SOURCE_TYPE}/g; s/@COMMIT@/${SHORT_SHA}/g; s/@BUILD_NUM@/${BUILD_NUM}/g" "$STAGE_DIR/module.prop" "$STAGE_DIR/customize.sh"

cp "${KO_DIR}/zram.ko" "$STAGE_DIR/module/zram.ko"
cp "${KO_DIR}/zsmalloc.ko" "$STAGE_DIR/module/zsmalloc.ko"
[ -f "${KO_DIR}/encore_fas.ko" ] && cp "${KO_DIR}/encore_fas.ko" "$STAGE_DIR/module/encore_fas.ko"
[ -f "${KO_DIR}/br_netfilter.ko" ] && cp "${KO_DIR}/br_netfilter.ko" "$STAGE_DIR/module/br_netfilter.ko"
[ -f "${KO_DIR}/ath.ko" ]          && cp "${KO_DIR}/ath.ko"          "$STAGE_DIR/module/ath.ko"
[ -f "${KO_DIR}/ath9k_hw.ko" ]    && cp "${KO_DIR}/ath9k_hw.ko"    "$STAGE_DIR/module/ath9k_hw.ko"
[ -f "${KO_DIR}/ath9k_common.ko" ] && cp "${KO_DIR}/ath9k_common.ko" "$STAGE_DIR/module/ath9k_common.ko"
[ -f "${KO_DIR}/8188gu.ko" ] && cp "${KO_DIR}/8188gu.ko" "$STAGE_DIR/module/8188gu.ko"
[ -f "${KO_DIR}/ath9k_htc.ko" ]  && cp "${KO_DIR}/ath9k_htc.ko"  "$STAGE_DIR/module/ath9k_htc.ko"
[ -f "${KO_DIR}/mac80211.ko" ] && cp "${KO_DIR}/mac80211.ko" "$STAGE_DIR/module/mac80211.ko"
[ -f "${KO_DIR}/cfg80211.ko" ] && cp "${KO_DIR}/cfg80211.ko" "$STAGE_DIR/module/cfg80211.ko"
# cfg80211 overlay — replaces vendor cfg80211 with GKI build at boot
# Both /vendor/lib/modules and /vendor_dlkm/lib/modules need covering:
# vendor_dlkm is a separate erofs partition loaded at t=4s before NoMount
if [ -f "${KO_DIR}/cfg80211.ko" ]; then
  mkdir -p "$STAGE_DIR/system/vendor/lib/modules"
  cp "${KO_DIR}/cfg80211.ko" "$STAGE_DIR/system/vendor/lib/modules/cfg80211.ko"
  mkdir -p "$STAGE_DIR/system/vendor_dlkm/lib/modules"
  cp "${KO_DIR}/cfg80211.ko" "$STAGE_DIR/system/vendor_dlkm/lib/modules/cfg80211.ko"
fi

chmod +x "$STAGE_DIR/customize.sh" "$STAGE_DIR/post-fs-data.sh" "$STAGE_DIR/action.sh"
[ -f "$STAGE_DIR/service.sh" ] && chmod +x "$STAGE_DIR/service.sh"

# Seiran app: goes in before signing so it is covered by the hash list
[ -f "${SEIRAN_APP_APK:-}" ] || { echo "[ERROR] SEIRAN_APP_APK not set or missing"; exit 1; }
mkdir -p "$STAGE_DIR/app"
cp "$SEIRAN_APP_APK" "$STAGE_DIR/app/seiran.apk"

bash "$(cd "$(dirname "$0")" && pwd)/signing/ci-sign.sh" "$STAGE_DIR"

rm -f "$OUT_ZIP"
(cd "$STAGE_DIR" && zip -r9 -q "$OUT_ZIP" . -x ".*")

echo "[OK] ${SOURCE_TYPE}: packaged $(basename "$OUT_ZIP")"
