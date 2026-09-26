#!/usr/bin/env bash
# pack-zip.sh — pack AnyKernel3 zip per variant
# env: SOURCE_TYPE, KSU_TYPE, BUILD_TYPE, WORK_DIR
set -e

: "${SOURCE_TYPE:?}"
: "${KSU_TYPE:?}"
: "${WORK_DIR:?}"
: "${BUILD_TYPE:-stable}"

AK3_REPO="https://github.com/superuseryu/AnyKernel3"
IMAGE="${WORK_DIR}/out/dist/Image"

[ -f "$IMAGE" ] || { echo "[ERROR] Image not found: $IMAGE"; exit 1; }

# Read kernel sublevel from build output — extract X.Y.Z only, drop uname suffix
VERSION_FILE="${WORK_DIR}/out/dist/kernel_version.txt"
_raw=$([ -f "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" || echo "5.15.x")
KERNEL_VERSION=$(echo "$_raw" | grep -oP '^\d+\.\d+\.\d+' || echo "$_raw")

# Derive labels from env
case "${SOURCE_TYPE}" in
  gki) SRC_LABEL="GKI" ;;
  clo) SRC_LABEL="CLO" ;;
  *)   SRC_LABEL="${SOURCE_TYPE^^}" ;;
esac

case "${KSU_TYPE}" in
  ksun) KSU_LABEL="KSU-Next" ;;
  rsku) KSU_LABEL="ReSukiSU"      ;;
  none) KSU_LABEL="NoKSU"   ;;
  *)    KSU_LABEL="${KSU_TYPE}" ;;
esac

[ "$BUILD_TYPE" = "testing" ] && SUFFIX="-testing" || SUFFIX=""
ZIP_NAME="AK3-${SRC_LABEL}-${KSU_LABEL}-${KERNEL_VERSION}-$(date +'%Y-%m')${SUFFIX}.zip"

# Named image used by AIO pack-release.sh when extracting
case "$KSU_TYPE" in
  ksun) IMAGE_NAME="Image.gki.ksu"  ;;
  rsku) IMAGE_NAME="Image.gki.rsku" ;;
  none) IMAGE_NAME="Image.gki.noksu";;
  *)    IMAGE_NAME="Image"          ;;
esac

cd "$WORK_DIR"
git clone --depth=1 "$AK3_REPO" ak3_tmp
[ -d "${GITHUB_WORKSPACE}/anykernel/ramdisk" ] && cp -r "${GITHUB_WORKSPACE}/anykernel/ramdisk/." "ak3_tmp/ramdisk/"

# Per-variant ZIP: only Image (for flashing) — no named copy to keep size lean
cp "$IMAGE" "ak3_tmp/Image"

# Bundle zram modules if available (globally, all variants)
KO_DIR="${WORK_DIR}/out/dist/ko"
if [ -f "${KO_DIR}/zram.ko" ] && [ -f "${KO_DIR}/zsmalloc.ko" ]; then
  mkdir -p "ak3_tmp/modules/system/lib/modules"
  cp "${KO_DIR}/zram.ko"     "ak3_tmp/modules/system/lib/modules/"
  cp "${KO_DIR}/zsmalloc.ko" "ak3_tmp/modules/system/lib/modules/"
  echo "[INFO] zram modules bundled into zip"
else
  echo "[WARN] zram.ko/zsmalloc.ko not found in ${KO_DIR} — skipping module bundle"
fi

cd ak3_tmp
zip -r9 "../${ZIP_NAME}" * -x .git/*
cd ..
rm -rf ak3_tmp

SIZE_MB=$(echo "scale=2; $(stat -c%s "$ZIP_NAME") / 1024 / 1024" | bc | sed 's/^\./0./')
echo "✅ Packed: $ZIP_NAME ($SIZE_MB MB)"

echo "ZIP_NAME=$ZIP_NAME"         >> "${GITHUB_ENV:-/dev/null}"
echo "ZIP_SIZE_MB=$SIZE_MB"       >> "${GITHUB_ENV:-/dev/null}"
echo "DATE_TAG=$BUILD_DATE"       >> "${GITHUB_ENV:-/dev/null}"
echo "IMAGE_NAME=$IMAGE_NAME"     >> "${GITHUB_ENV:-/dev/null}"
