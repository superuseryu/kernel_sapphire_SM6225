# Features

## Core Features

**Scheduler**
- [BORE](https://github.com/firelzrd/bore-scheduler) — burst-oriented CFS latency tuning
- CASS — Capacity Aware Superset Scheduler
- prefer_silver — silver-cluster affinity layer on top of CASS
- [NAP](https://github.com/firelzrd/nap) — cpuidle governor (fixedpoint steambot12)
- Battery-oriented tuning: WALT early-migration thresholds, `sched_nr_migrate`, `watermark_scale_factor`, `vm_swappiness`, yield ratelimit, LIFO wait accept

**Memory**
- MGLRU forced on (`CONFIG_LRU_GEN_ENABLED=y`)
- [le9uo](https://github.com/firelzrd/le9uo) workingset protection
- ZRAM multi-comp + zram-ir tiered recompression with huge/idle-page recompression — requires [Seiran Core](#seiran-core-module)
- zstd upgraded to v1.5.7

**I/O**
- ADIOS (Adaptive Deadline I/O Scheduler) multi-queue scheduler

**CPU governor**
- [Reflex](https://github.com/firelzrd/reflex) cpufreq governor (backported)

**Network**
- BBRv3 + Westwood TCP congestion control · FQ default qdisc (CAKE / PIE also available)
- TCP write buffer increased to 16MB

**Security / stability**
- CVE-2026-43499 rtmutex ghostlock UAF fix
- CVE-2026-64560 posix CPU timers UAF fix

**Other**
- Thin LTO
- HZ=300
- kbuild modpost/kallsyms speedup
- ntsync (Wine/Proton sync primitives)
- arm64 memcmp optimization for Snapdragon 685
- timer slack reduced to 50ns
- DRM/mi_disp, NFC, WLAN HDD, CMN MLME logspam filtering
- Droidspaces support (see below)

---


## Seiran Core Module

> [!CAUTION]
> **Required — no exceptions.** Without this module, ZRAM will not work at all — `zram0` won't come up, swap won't run, and RAM management will be worse than stock.

The kernel ZIP alone is not enough. `CONFIG_ZRAM=m` means `zram.ko`/`zsmalloc.ko` are loadable modules, not baked into the kernel image. Seiran Core is the KSU/Magisk module that loads them.

**What it does:** loads `zram.ko` + `zsmalloc.ko` with multi-comp + zram-ir tiered recompression, then sets NAP as cpuidle governor, ADIOS as I/O scheduler, and Reflex as cpufreq governor — all at `post-fs-data`.

**Download:**
- **GitHub Release:** `seiran-core.zip` attached alongside the kernel ZIP.
- **Telegram:** [t.me/tmplogchat](https://t.me/tmplogchat)

**Install:** requires a module manager (KSU/Magisk). Install from the Modules tab — do not flash from recovery.
- **NoKSU:** root first via Magisk or KSU-Next/SukiSU-Ultra, then install from there.

> [!NOTE]
> Universal — works across all variants (GKI/CLO × KSU-Next/SukiSU/NoKSU).

---

## Droidspaces Support

This kernel ships with full [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) container support out of the box.

Enabled configs: `SYSVIPC` · `IPC_NS` · `PID_NS` · `POSIX_MQUEUE` · `DEVTMPFS` · Netfilter extras

kABI fix applied for GKI < 6.12 to prevent vendor module crashes on boot.

> [!CAUTION]
> Droidspaces isn't compatible with SuSFS. Disable SuSFS before using Droidspaces.

Confirmed working on sapphire — see [community-supported devices](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/community-supported-devices.md).

---

## Patch Inventory

### Stable (`patches/common/`)

Stable patches applied to all variants (GKI, CLO, GKI-Compat). See [`patches/common/`](../patches/common/) for the full list.

### GKI-Compat only (`patches/gki-compat-only/`)

Compatibility shims on top of `patches/common/` to keep the GKI-Compat tree (pinned to 5.15.123) building clean. See [`patches/gki-compat-only/`](../patches/gki-compat-only/).

### Testing (`patches/testing/`)

Patches under evaluation — may be unstable or variant-specific. See [`patches/testing/`](../patches/testing/).

---

Maintainer config reference: [config-blacklist.md](./config-blacklist.md)
