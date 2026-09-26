MODDIR=${0%/*}
ZRAM_DEV=/dev/block/zram0
ZRAM_SYS=/sys/block/zram0

ORIG_MOD_DESCRIPTION=$(grep -m1 -E '^description=' ${MODDIR}/module.prop.orig | cut -d'=' -f2)
grep -vE '^description=' ${MODDIR}/module.prop.orig > ${MODDIR}/module.prop

set_status() {
	echo "description=[$1] $ORIG_MOD_DESCRIPTION" >> ${MODDIR}/module.prop
}

# Two possible orderings on different devices:
#  (a) native swapon-on-zram already happened before post-fs-data runs
#      -> we must carefully swapoff/preserve-disksize/restore around the swap
#  (b) post-fs-data runs BEFORE native swapon
#      -> nothing is using zram0 yet, we can just swap the modules in
#         directly; whatever runs swapon later will use our module.
IS_SWAP_ACTIVE=0
ORIG_DISKSIZE=""
if grep -q "^${ZRAM_DEV}" /proc/swaps 2>/dev/null; then
	IS_SWAP_ACTIVE=1
	ORIG_DISKSIZE=$(cat ${ZRAM_SYS}/disksize 2>/dev/null)
fi

if [ "$IS_SWAP_ACTIVE" = "1" ]; then
	swapoff ${ZRAM_DEV} 2>/dev/null
fi
[ -e ${ZRAM_SYS}/reset ] && echo 1 > ${ZRAM_SYS}/reset 2>/dev/null
# zram depends on zsmalloc, so unload in dependent-first order (best-effort;
# harmless if not currently loaded, e.g. case (b) where nothing loaded it yet).
rmmod zram 2>/dev/null
rmmod zsmalloc 2>/dev/null

# Load dependency first, then the dependent module.
insmod ${MODDIR}/module/zsmalloc.ko 2>/dev/null
insmod ${MODDIR}/module/zram.ko 2>/dev/null

# Fail-safe, not fail-dangerous: if our modules didn't load, don't attempt a
# risky live fallback to reload the stock .ko by guessing its path — worst
# case here is no zram/swap until reboot, which is recoverable via normal
# init on the next boot.
if [ ! -e ${ZRAM_SYS}/disksize ]; then
	set_status "😥 zram.ko/zsmalloc.ko failed to load"
	exit 0
fi

echo "algo=lz4 priority=1" > ${ZRAM_SYS}/recomp_algorithm 2>/dev/null

if [ "$IS_SWAP_ACTIVE" = "1" ]; then
	# Case (a): restore the swap we tore down above, on the new module.
	echo ${ORIG_DISKSIZE} > ${ZRAM_SYS}/disksize 2>/dev/null
	mkswap ${ZRAM_DEV} >/dev/null 2>&1
	if swapon -p -2 ${ZRAM_DEV} 2>/dev/null; then
		set_status "😋 zram.ko (multi-comp+IR) loaded, swap restored"
	else
		set_status "😥 modules loaded but swapon failed — reboot recommended"
	fi
else
	# Case (b): nothing was using zram0 yet — our module is now in place,
	# whatever runs swapon later (vold, init) will use it.
	set_status "😋 zram.ko (multi-comp+IR) loaded ahead of native swapon"
fi

# NAP cpuidle governor — switch after qcom_lpm loads at boot
# qcom_lpm wins at boot (rating 50 > NAP 18) but does not re-register
# post-suspend, so a one-shot write here is permanent until next reboot.
echo nap > /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null

# ADIOS I/O scheduler — storage devices only (dm/loop/ram don't support schedulers)
for dev in /sys/block/sd*/queue/scheduler; do
	echo adios > "$dev" 2>/dev/null
done

# Reflex cpufreq governor — SM6225 has 2 fixed clusters (little: policy0, big: policy4)
echo reflex > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
echo reflex > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null

sync
