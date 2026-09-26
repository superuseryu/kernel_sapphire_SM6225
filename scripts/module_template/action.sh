#!/system/bin/sh
if [ -f /sys/block/zram0/recomp_algorithm ]; then
	echo "- multi-comp active"
	echo "- recomp_algorithm: $(cat /sys/block/zram0/recomp_algorithm)"
	echo "- comp_algorithm:   $(cat /sys/block/zram0/comp_algorithm)"
else
	echo "- zram.ko multi-comp not active."
	echo "- Reboot may be required, or check the module description in Manager."
fi
sleep 1s

echo "- cpuidle governor: $(cat /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null || echo unknown)"
echo "- I/O scheduler: $(cat $(find /sys/block/sd*/queue/scheduler 2>/dev/null | head -1) 2>/dev/null | grep -oE '\[[^]]+\]' | tr -d '[]' || echo unknown)"
echo "- cpufreq governor (policy0): $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || echo unknown)"
echo "- cpufreq governor (policy4): $(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null || echo unknown)"
