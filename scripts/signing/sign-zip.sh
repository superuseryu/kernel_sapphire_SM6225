#!/usr/bin/env bash
# usage: sign-zip.sh <stage_dir> <private_key_abs> <pub.raw_abs> <verify_bin_abs>
set -euo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="${1:?stage dir}"; KEY="${2:?key}"; PUB="${3:?pub.raw}"; VBIN="${4:?verify bin}"
mkdir -p "$DIR/seiran-verify"
cp "$VBIN" "$DIR/seiran-verify/verify"
cp "$PUB"  "$DIR/seiran-verify/pub.raw"
cp "$HERE/verify-zip.sh" "$DIR/seiran-verify/verify-zip.sh"
chmod 755 "$DIR/seiran-verify/verify" "$DIR/seiran-verify/verify-zip.sh"
cd "$DIR"
rm -f SHA256SUMS SHA256SUMS.sig
find . -type f ! -path '*/.*' ! -name SHA256SUMS ! -name SHA256SUMS.sig -print0 \
  | sort -z | xargs -0 sha256sum > SHA256SUMS
openssl pkeyutl -sign -rawin -inkey "$KEY" -in SHA256SUMS -out SHA256SUMS.sig
chmod 644 SHA256SUMS SHA256SUMS.sig "$DIR/seiran-verify/pub.raw"
echo "[OK] signed $(wc -l < SHA256SUMS) files"
