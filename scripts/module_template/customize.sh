SKIPUNZIP=1
$BOOTMODE || abort "! Install this module from Magisk/KernelSU Manager, not recovery."

# Verify signature + hashes before anything is installed
V="${TMPDIR:-/data/local/tmp}/seiran-v"
rm -rf "$V"; mkdir -p "$V"
unzip -o "$ZIPFILE" -d "$V" >&2 || abort "! unzip failed"
chmod 755 "$V/seiran-verify/verify"
sh "$V/seiran-verify/verify-zip.sh" "$V" || abort "! Verification failed. Download the official release again."
ui_print "- Signature OK, installing"
unzip -o "$ZIPFILE" -x 'seiran-verify/*' SHA256SUMS SHA256SUMS.sig -d "$MODPATH" >&2
rm -rf "$V"
chmod +x "$MODPATH/tools/inotifywait"

cat /proc/version | grep -qE '^Linux version (5\.15|6\.12)\.' || abort "! This module only supports the sapphire 5.15 kernel."

description="zram.ko+zsmalloc.ko (multi-comp+zram-ir) + NAP cpuidle + ADIOS + Reflex · @COMMIT@"
unset description
cp ${MODPATH}/module.prop ${MODPATH}/module.prop.orig

