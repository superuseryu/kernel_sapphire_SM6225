#!/usr/bin/env bash
# usage: build-app.sh <out.apk>
# env: SEIRAN_APP_KS_B64, SEIRAN_APP_KS_PASS (both required)
#      GRADLE_VERSION (default 9.5.1)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out apk path}"
GRADLE_VERSION="${GRADLE_VERSION:-9.5.1}"
# SHA-256 of the app signing certificate (seiran-app.jks)
EXPECT_FP="bb25e4e42a8aebfff42ad5c4b710fe0a88ef72c800685c36600970667dc42482"

if [ -z "${SEIRAN_APP_KS_B64:-}" ] || [ -z "${SEIRAN_APP_KS_PASS:-}" ]; then
  echo "[ERROR] app keystore secrets not set, refusing to build an unsigned app"
  exit 1
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
( umask 077; printf '%s' "$SEIRAN_APP_KS_B64" | base64 -d > "$T/ks.jks" )

if ! command -v gradle >/dev/null 2>&1; then
  U="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
  curl -fsSL -o "$T/gradle.zip" "$U"
  echo "$(curl -fsSL "$U.sha256")  $T/gradle.zip" | sha256sum -c -
  unzip -q "$T/gradle.zip" -d "$T"
  export PATH="$T/gradle-${GRADLE_VERSION}/bin:$PATH"
fi

SEIRAN_APP_KS_FILE="$T/ks.jks" SEIRAN_APP_KS_PASS="$SEIRAN_APP_KS_PASS" \
  gradle --no-daemon -p "$ROOT/app" assembleRelease

shopt -s nullglob
apks=("$ROOT"/app/build/outputs/apk/release/*.apk)
[ "${#apks[@]}" -eq 1 ] || { echo "[ERROR] expected 1 release apk, got ${#apks[@]}"; exit 1; }

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
SIGNER=""
[ -n "$SDK" ] && SIGNER="$(find "$SDK/build-tools" -name apksigner 2>/dev/null | sort -V | tail -1)"
if [ -n "$SIGNER" ]; then
  FP="$("$SIGNER" verify --print-certs "${apks[0]}" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | tr -d ' ')"
  [ "$FP" = "$EXPECT_FP" ] || { echo "[ERROR] app cert mismatch: $FP"; exit 1; }
  echo "[OK] app cert $FP"
else
  echo "[WARN] apksigner not found, signer not verified"
fi

cp "${apks[0]}" "$OUT"
echo "[OK] built $OUT"
