#!/usr/bin/env bash
# usage: build-verify.sh <out_binary>   env: CC (default gcc)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?out path}"
cd "$HERE"
sha256sum -c tweetnacl.SHA256
${CC:-gcc} -static -O2 -I. -o "$OUT" verify.c tweetnacl.c
echo "[OK] built $OUT"
