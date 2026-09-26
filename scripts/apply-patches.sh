#!/usr/bin/env bash
# apply-patches.sh — apply patches from patches/ folder + WildKernels patches
# env: SOURCE_TYPE, KSU_TYPE, BUILD_TYPE, KERNEL_SRC, DEFCONFIG
set -e

: "${KERNEL_SRC:?}"
: "${SOURCE_TYPE:?}"
: "${KSU_TYPE:?}"
: "${BUILD_TYPE:-stable}"
: "${WORK_DIR:=$GITHUB_WORKSPACE}"

source /tmp/apply_patch.sh
cd "$KERNEL_SRC"

# WildKernels patches
echo "=== Applying upstream optimization patches ==="
BASE="https://raw.githubusercontent.com/WildKernels/kernel_patches/refs/heads/main/common"

apply_patch "$BASE/ntsync/ntsync_base.patch"                       "ntsync_base"
apply_patch "$BASE/ntsync/ntsync_compat_android13-5.15.patch"      "ntsync_compat_android13-5.15"
apply_patch "$BASE/IPv6_NAT_FIX.patch"                             "IPv6_NAT_FIX"
apply_patch "$BASE/add_limitation_scaling_min_freq.patch"          "add_limitation_scaling_min_freq"
apply_patch "$BASE/add_timeout_wakelocks_globally.patch"           "add_timeout_wakelocks_globally"
apply_patch "$BASE/adjust_cpu_scan_order.patch"                    "adjust_cpu_scan_order"
apply_patch "$BASE/avoid_extra_s2idle_wake_attempts.patch"         "avoid_extra_s2idle_wake_attempts"
apply_patch "$BASE/clear_page_16bytes_align.patch"                 "clear_page_16bytes_align"
apply_patch "$BASE/disable_cache_hot_buddy.patch"                  "disable_cache_hot_buddy"
apply_patch "$BASE/f2fs_enlarge_min_fsync_blocks.patch"            "f2fs_enlarge_min_fsync_blocks"
apply_patch "$BASE/f2fs_reduce_congestion.patch"                   "f2fs_reduce_congestion"
apply_patch "$BASE/file_struct_8bytes_align.patch"                 "file_struct_8bytes_align"
apply_patch "$BASE/increase_ext4_default_commit_age.patch"         "increase_ext4_default_commit_age"
apply_patch "$BASE/increase_sk_mem_packets.patch"                  "increase_sk_mem_packets"
apply_patch "$BASE/int_sqrt.patch"                                 "int_sqrt"
apply_patch "$BASE/mem_opt_prefetch.patch"                         "mem_opt_prefetch"
apply_patch "$BASE/minimise_wakeup_time.patch"                     "minimise_wakeup_time"
apply_patch "$BASE/optimized_mem_operations.patch"                 "optimized_mem_operations"
apply_patch "$BASE/re_write_limitation_scaling_min_freq.patch"     "re_write_limitation_scaling_min_freq"
apply_patch "$BASE/reduce_cache_pressure.patch"                    "reduce_cache_pressure"
apply_patch "$BASE/reduce_freeze_timeout.patch"                    "reduce_freeze_timeout"
apply_patch "$BASE/reduce_gc_thread_sleep_time.patch"              "reduce_gc_thread_sleep_time"
apply_patch "$BASE/silence_irq_cpu_logspam.patch"                  "silence_irq_cpu_logspam"
apply_patch "$BASE/silence_system_logspam.patch"                   "silence_system_logspam"
apply_patch "$BASE/unicode_bypass_fix_6.1-.patch"                  "unicode_bypass_fix_6.1-"
apply_patch "$BASE/use_unlikely_wrap_cpufreq.patch"                "use_unlikely_wrap_cpufreq"

# Local common patches
echo "=== Applying local common patches ==="
PATCHES_DIR="$WORK_DIR/patches"
if [ -d "$PATCHES_DIR/common" ]; then
  for PATCH in "$PATCHES_DIR/common"/*.patch; do
    [ -f "$PATCH" ] || continue
    apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
  done
fi

# Source-type patches
echo "=== Applying $SOURCE_TYPE-specific patches ==="
if [ -d "$PATCHES_DIR/${SOURCE_TYPE}-only" ]; then
  for PATCH in "$PATCHES_DIR/${SOURCE_TYPE}-only"/*.patch; do
    [ -f "$PATCH" ] || continue
    apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
  done
fi

# Testing patches
if [ "$BUILD_TYPE" = "testing" ]; then
  echo "=== Applying testing patches ==="
  if [ -d "$PATCHES_DIR/testing" ]; then
    for PATCH in "$PATCHES_DIR/testing"/*.patch; do
      [ -f "$PATCH" ] || continue
      apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
    done
  fi
fi

echo "[OK] All patches applied"
