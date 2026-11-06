#!/usr/bin/env bash
# usage: ci-sign.sh <stage_dir>
# env: SEIRAN_SIGN_KEY (PEM text, required)
#      SEIRAN_VERIFY_BIN (optional prebuilt aarch64 binary)
#      CC (default aarch64-linux-gnu-gcc)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(cd "${1:?stage dir}" && pwd)"
[ -n "${SEIRAN_SIGN_KEY:-}" ] || { echo "[ERROR] SEIRAN_SIGN_KEY not set, refusing to make an unsigned zip"; exit 1; }
umask 077
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "$SEIRAN_SIGN_KEY" > "$T/key.pem"
VBIN="${SEIRAN_VERIFY_BIN:-}"
if [ -z "$VBIN" ]; then
  VBIN="$T/verify"
  CC="${CC:-aarch64-linux-gnu-gcc}" bash "$HERE/build-verify.sh" "$VBIN"
fi
if command -v file >/dev/null 2>&1; then
  file "$VBIN" | grep -q 'ARM aarch64' || { echo "[ERROR] verify binary is not aarch64"; exit 1; }
fi
bash "$HERE/sign-zip.sh" "$DIR" "$T/key.pem" "$HERE/pub.raw" "$VBIN"
