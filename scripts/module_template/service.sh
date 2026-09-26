#!/system/bin/sh
# service.sh — runs after boot_completed, overrides ROM init.rc governor reset
# Wait for boot_completed then sleep to outlast ROM's late-init governor reset
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done
sleep 3
# Reflex cpufreq governor — SM6225 has 2 fixed clusters (little: policy0, big: policy4)
echo reflex > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
echo reflex > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor 2>/dev/null
