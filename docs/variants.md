# Variants

## Variants

| Variant | Source | Root | Extras |
|---------|--------|------|--------|
| GKI-Ksun | AOSP LTS | KernelSU-Next + SUSFS | BBG |
| GKI-SukiSU | AOSP LTS | SukiSU-Ultra + SUSFS | KPM |
| GKI-NoKSU | AOSP LTS | Vanilla | — |
| CLO-Ksun | CodeLinaro | KernelSU-Next + SUSFS | BBG |
| CLO-SukiSU | CodeLinaro | SukiSU-Ultra + SUSFS | KPM |
| CLO-NoKSU | CodeLinaro | Vanilla | — |
| GKI-Compat-Ksun | AOSP 2023-10 (deprecated) | KernelSU-Next + SUSFS | BBG |
| GKI-Compat-SukiSU | AOSP 2023-10 (deprecated) | SukiSU-Ultra + SUSFS | KPM |
| GKI-Compat-NoKSU | AOSP 2023-10 (deprecated) | Vanilla | — |

**Supported Android versions:** GKI-Compat targets an older GKI ABI and works across Android 13–17 — use it if your ROM is on Android 13 or 14. Main **GKI / CLO** target the newer interfaces and are for Android 15+ ROMs.

---

## Build Details

| | GKI | GKI-Compat | CLO |
|--|-----|------------|-----|
| Source | `android.googlesource.com/kernel/common` | `android.googlesource.com/kernel/common` | `git.codelinaro.org/clo/la/kernel/msm-5.15` |
| Branch | `android13-5.15-lts` | `deprecated/android13-5.15-2023-10` | `kernel.lnx.5.15.r1-rel` |
| Config fragment | — | — | `vendor/bengal_GKI.config` |
| Toolchain | Clang r450784e | Clang r450784e | ZyC Clang 14.0.6 |
| LTO | Thin | Thin | Thin |
