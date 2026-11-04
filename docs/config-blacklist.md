# Config Blacklist

> Maintainer reference only. Not user-facing.

## Do not re-add

| Config | Root Cause |
|---|---|
| `CONFIG_PRINTK` | Removes `printk` from vmlinux exports — all vendor `.ko` fail |
| `CONFIG_PSI` | LMKD hard dependency |
| `CONFIG_SCHED_DEBUG` | `sysctl_sched_features` in GKI ABI contract |
| `CONFIG_SCHEDSTATS` | `struct sched_statistics` body is `#ifdef CONFIG_SCHEDSTATS` but embedded unconditionally in `struct sched_entity` — disabling shrinks the struct, shifting all subsequent fields (avg, KABI reserves, EEVDF) and breaking vendor `.ko` ABI |
| `CONFIG_TASK_IO_ACCOUNTING` | `struct task_io_accounting` has 3 conditional fields (`read_bytes`, `write_bytes`, `cancelled_write_bytes`) under `#ifdef CONFIG_TASK_IO_ACCOUNTING`, embedded unconditionally in `task_struct.ioac` — disabling shrinks `task_struct`, KMI break |
| `CONFIG_TASK_XACCT` | Same struct as above — 5 fields (`rchar`, `wchar`, `syscr`, `syscw`, `syscfs`) under `#ifdef CONFIG_TASK_XACCT`, also in `task_struct.ioac` — disabling shrinks `task_struct`, KMI break |
| `CONFIG_PAGE_OWNER` | Disables `PAGE_EXTENSION` → vendor `.ko` `page_ext_get()` crash |
| `CONFIG_DEBUG_BUGVERBOSE` | `struct bug_entry` loses `file`+`line` → `.bug_table` misparse in vendor `.ko` |
| `CONFIG_UCLAMP_BUCKETS_COUNT` | Device value is `20` — changing breaks vendor `.ko` struct alignment |
| `CONFIG_CGROUP_DEVICE` | Required by `android-base.config` |
| `CONFIG_CFG80211=y` | Must be `=m` — Qualcomm `wlan.ko` module dep chain |
| `CONFIG_MAC80211=y` | Same as `CFG80211` |
| `CONFIG_IP_TABLES=y` | Must be `=m` — `netd` expects `modprobe` |
| `CONFIG_TIPC=n` | Bootloop at boot animation on SM6225 (kernel boots, Android init reaches SurfaceFlinger, stuck at early animation frames then reboots) — bisect confirmed; root cause unknown, suspected vendor HAL or system service implicit TIPC socket dependency |

## Safe to disable

| Config | Note |
|---|---|
| `CONFIG_UBSAN` | Bisect confirmed |
| `CONFIG_RCU_TRACE` | Doesn't exist in 5.15, no-op |
| `CONFIG_DEBUG_MISC` | Pure Kconfig wrapper, zero runtime impact |
