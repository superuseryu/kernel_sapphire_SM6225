#!/bin/sh
# usage: verify-zip.sh <dir> [allowed runtime paths, space-separated, exact]
export LC_ALL=C
D="$1"; ALLOW="$2"; V="$D/seiran-verify"
[ -x "$V/verify" ] || { echo "FAIL: verifier missing"; exit 1; }
echo "Signer fingerprint: $(sha256sum "$V/pub.raw" | cut -d' ' -f1)"
"$V/verify" "$V/pub.raw" "$D/SHA256SUMS" "$D/SHA256SUMS.sig" || { echo "FAIL: bad signature"; exit 1; }
cd "$D" || exit 1
# Verify checksum of all files in manifest
MISMATCH=$(sha256sum -c SHA256SUMS 2>&1 | grep -E ':[[:space:]]*FAILED' | sed 's/:[[:space:]]*FAILED.*//' | tr -d '\r')
if [ -n "$MISMATCH" ]; then
  # Allow Image mismatch ONLY IF it was patched by SukiSU KPM (kpimg injection)
  # All other files in the zip (scripts, tools, modules) must match exactly.
  if [ "$MISMATCH" = "./Image" ] || [ "$MISMATCH" = "Image" ]; then
    IS_KPM=0
    case "$D" in
      *com.sukisu*|*kernel_flash*) IS_KPM=1 ;;
    esac
    case "$PWD" in
      *com.sukisu*|*kernel_flash*) IS_KPM=1 ;;
    esac
    if grep -q "kpimg" ./Image 2>/dev/null || grep -a -q "kpimg" ./Image 2>/dev/null; then
      IS_KPM=1
    fi
    if [ "$IS_KPM" = "1" ]; then
      echo "NOTICE: SukiSU KPM patch detected on Image (verified remaining files)"
    else
      echo "FAIL: hash mismatch on $MISMATCH"
      exit 1
    fi
  else
    echo "FAIL: hash mismatch or missing file"
    exit 1
  fi
fi
find . -type f ! -path '*/.*' ! -name SHA256SUMS ! -name SHA256SUMS.sig | sort > .sv.a
sed 's/^[0-9a-f]*  //' SHA256SUMS | sort > .sv.b
for p in $ALLOW; do grep -vxF "$p" .sv.a > .sv.c; mv -f .sv.c .sv.a; done
if cmp -s .sv.a .sv.b; then rm -f .sv.a .sv.b; echo "OK: valid"; exit 0; fi
echo "dbg only in one list:"; sort .sv.a .sv.b | uniq -u | head -20
rm -f .sv.a .sv.b
echo "FAIL: extra file in zip"; exit 1
