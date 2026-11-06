#!/bin/sh
# usage: verify-zip.sh <dir> [allowed runtime paths, space-separated, exact]
export LC_ALL=C
D="$1"; ALLOW="$2"; V="$D/seiran-verify"
[ -x "$V/verify" ] || { echo "FAIL: verifier missing"; exit 1; }
echo "Signer fingerprint: $(sha256sum "$V/pub.raw" | cut -d' ' -f1)"
"$V/verify" "$V/pub.raw" "$D/SHA256SUMS" "$D/SHA256SUMS.sig" || { echo "FAIL: bad signature"; exit 1; }
cd "$D" || exit 1
sha256sum -c SHA256SUMS >/dev/null 2>&1 || { echo "FAIL: hash mismatch or missing file"; exit 1; }
find . -type f ! -path '*/.*' ! -name SHA256SUMS ! -name SHA256SUMS.sig | sort > .sv.a
sed 's/^[0-9a-f]*  //' SHA256SUMS | sort > .sv.b
for p in $ALLOW; do grep -vxF "$p" .sv.a > .sv.c; mv -f .sv.c .sv.a; done
if cmp -s .sv.a .sv.b; then rm -f .sv.a .sv.b; echo "OK: valid"; exit 0; fi
echo "dbg only in one list:"; sort .sv.a .sv.b | uniq -u | head -20
rm -f .sv.a .sv.b
echo "FAIL: extra file in zip"; exit 1
