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

chmod +x "$STAGE_DIR/customize.sh" "$STAGE_DIR/post-fs-data.sh" "$STAGE_DIR/action.sh"
[ -f "$STAGE_DIR/service.sh" ] && chmod +x "$STAGE_DIR/service.sh"

rm -f "$OUT_ZIP"
(cd "$STAGE_DIR" && zip -r9 -q "$OUT_ZIP" . -x ".*")

echo "[OK] ${SOURCE_TYPE}: packaged $(basename "$OUT_ZIP")"
