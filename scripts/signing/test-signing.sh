#!/usr/bin/env bash
# local test, needs a host that can run the verify binary (aarch64)
# usage: test-signing.sh <key_abs> <pub.raw_abs> <verify_bin_abs>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; cd "$W"
mkdir -p stage/sub
echo a > stage/a.txt; echo b > stage/sub/b.txt; head -c 5000 /dev/urandom > stage/blob.bin
"$HERE/sign-zip.sh" stage "$1" "$2" "$3" >/dev/null
(cd stage && zip -r9 -q ../good.zip . -x '.*')
openssl genpkey -algorithm ED25519 -out other.key 2>/dev/null
fails=0; n=0
t(){ n=$((n+1)); rm -rf x; mkdir x
  if ! unzip -q "$2" -d x 2>/dev/null; then r=1; else
    [ -n "$3" ] && (cd x && eval "$3")
    sh x/seiran-verify/verify-zip.sh x >/dev/null 2>&1; r=$?; fi
  if [ "$r" = "$1" ]; then echo "PASS $n: $4"; else echo "FAIL $n: $4 (rc=$r)"; fails=$((fails+1)); fi; }
t 0 good.zip "" "original zip"
t 1 good.zip "printf X >> blob.bin" "1 file modified"
t 1 good.zip "echo z > extra.txt" "file added"
t 1 good.zip "rm sub/b.txt" "file deleted"
t 1 good.zip "echo evil > SHA256SUMS" "manifest replaced"
head -c 3000 good.zip > cut.zip; t 1 cut.zip "" "zip truncated"
t 1 good.zip "openssl pkeyutl -sign -rawin -inkey ../other.key -in SHA256SUMS -out SHA256SUMS.sig" "signed by other key"
cd /; rm -rf "$W"; exit $fails
