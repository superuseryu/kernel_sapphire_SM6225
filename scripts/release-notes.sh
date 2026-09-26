#!/usr/bin/env bash
# release-notes.sh — generate release body
set -e

: "${BUILD_TYPE:-stable}"
: "${WORKFLOW_TYPE:-aio}"
: "${RUN_URL:?}"
: "${REPO:?}"
: "${SHA:?}"

SHORT_SHA="${SHA:0:9}"
COMMIT_URL="https://github.com/${REPO}/commit/${SHA}"
BODY=""

# Compat restriction banner
if [ "$WORKFLOW_TYPE" = "compat" ]; then
  BODY="${BODY}> [!NOTE]"$'\n'
  BODY="${BODY}> GKI-Compat targets an older GKI ABI and works across Android 13–17. Use it if your ROM is on **Android 13 or 14**. On Android 15+, use main [Seiran-GKI](https://github.com/${REPO}/releases/latest) instead."$'\n\n'
fi

# Testing warning banner
if [ "$BUILD_TYPE" = "testing" ]; then
  BODY="${BODY}> [!WARNING]"$'\n'
  BODY="${BODY}> Testing build — debug stripped, perf/sched configs non-default. Expect rough edges."$'\n\n'
fi

BODY="${BODY}**KSU-Next Manager:** [Dev Build ↗](${KSUN_MANAGER_URL})"$'\n'
BODY="${BODY}**ReSukiSU Manager:** [Main Build ↗](${RSKU_MANAGER_URL})"$'\n'
BODY="${BODY}**SUSFS module:** [${SUSFS_VERSION}](${SUSFS_MODULE_URL})"$'\n'
if [ -n "${KERNEL_VERSION_GKI:-}" ] && [ -n "${KERNEL_VERSION_CLO:-}" ]; then
  BODY="${BODY}**Kernel base (GKI):** \`${KERNEL_VERSION_GKI}\`"$'\n'
  BODY="${BODY}**Kernel base (CLO):** \`${KERNEL_VERSION_CLO}\`"$'\n\n'
else
  BODY="${BODY}**Kernel base:** \`${KERNEL_VERSION}\`"$'\n\n'
fi
BODY="${BODY}**ZRAM Multi-Comp module:** \`seiran-core.zip\` — attached below & sent via [Telegram](https://t.me/tmplogchat)"$'\n\n'

if [ "$WORKFLOW_TYPE" = "compat" ]; then
  BODY="${BODY}**Variants:** GKI-Compat (KSU-Next · ReSukiSU · NoKSU)"$'\n'
  BODY="${BODY}**Supported:** Android 13+ (recommended if your ROM is A13/A14)"$'\n'
else
  BODY="${BODY}**Variants:** GKI (KSU-Next · ReSukiSU · NoKSU) · CLO (KSU-Next · ReSukiSU · NoKSU)"$'\n'
  BODY="${BODY}**Supported:** Android 15+"$'\n'
fi
BODY="${BODY}**ROM:** AOSP-based recommended — stock MIUI/HyperOS may have issues"$'\n'
BODY="${BODY}**Issues:** [t.me/home_yu_chat](https://t.me/home_yu_chat) · Critical → PM directly"$'\n\n'

# Manager version warning — all builds
BODY="${BODY}> [!IMPORTANT]"$'\n'
BODY="${BODY}> **Manager version must match kernel version.** Can't grant root / manager shows errors? Use the manager links above — not stable releases. Mismatch = can't grant root."$'\n\n'

BODY="${BODY}> [!NOTE]"$'\n'
BODY="${BODY}> **ZRAM module is universal** — one \`seiran-core.zip\` works across all variants (GKI/CLO × KSU-Next/ReSukiSU/NoKSU). Install it after flashing the kernel zip."$'\n\n'

BODY="${BODY}**Commit:** [\`${SHORT_SHA}\`](${COMMIT_URL})"$'\n'
BODY="${BODY}📋 **Per-build details:** [Run #${GITHUB_RUN_NUMBER} summary](${RUN_URL})"$'\n'
BODY="${BODY}> Full build logs in \`build-log-run*.zip\` below."

{
  echo "RELEASE_BODY<<EOREL"
  echo "$BODY"
  echo "EOREL"
} >> "${GITHUB_ENV:-/dev/null}"

echo "[OK] Release body generated"
