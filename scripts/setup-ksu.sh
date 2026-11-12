#!/usr/bin/env bash
# setup-ksu.sh — integrate KSU variant + SUSFS into kernel source
# env: KSU_TYPE (ksun|sksu|none), KERNEL_DIR, WORK_DIR
# optional env: KSUN_TAG_PIN, SKSU_TAG_PIN — if set, checkout that exact tag
#   instead of floating branch HEAD. Used only by check-updates.yml's verify
#   gate to test a specific candidate tag before it's committed to
#   source-pins.json. Normal builds never set these, so day-to-day behavior
#   (float + record detected tag) is unchanged.
set -e

: "${KSU_TYPE:?}"
: "${KERNEL_DIR:?}"
: "${WORK_DIR:?}"

git config --global init.defaultBranch main
git config --global advice.addEmbeddedRepo false

cd "$KERNEL_DIR"

_link_ksu_driver() {
  local DIR="$1"   # KernelSU-Next or SukiSU-Ultra
  [ ! -L "drivers/kernelsu" ] && [ ! -d "drivers/kernelsu" ] && \
    ln -sf "../${DIR}" drivers/kernelsu
  grep -q "obj-.*kernelsu" drivers/Makefile || \
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
  grep -q "kernelsu/Kconfig" drivers/Kconfig || \
    echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
}

_fix_susfs_fake_state() {
  # Replace fake_state with selinux_state (pershoot KSU-Next dropped fake_state)
  for f in security/selinux/hooks.c security/selinux/selinuxfs.c; do
    [ -f "$f" ] || continue
    python3 - "$f" <<'EOF'
import sys, subprocess
path = sys.argv[1]
src = open(path).read()
replacements = [
    ('#ifdef CONFIG_KSU_SUSFS\nextern struct selinux_state fake_state;\nextern bool ksu_selinux_hide_running __read_mostly;\n#endif // #ifdef CONFIG_KSU_SUSFS',
     '#ifdef CONFIG_KSU_SUSFS\nextern bool ksu_selinux_hide_running __read_mostly;\n#endif // #ifdef CONFIG_KSU_SUSFS'),
    ('int fake_error = security_context_to_sid(&fake_state, value, size, &tmp_sid, GFP_KERNEL);',
     'int fake_error = security_context_to_sid(&selinux_state, value, size, &tmp_sid, GFP_KERNEL);'),
    ('extern struct selinux_state fake_state;\n',
     ''),
    ('security_context_to_sid(&fake_state, buf, size, &sid, GFP_KERNEL)',
     'security_context_to_sid(&selinux_state, buf, size, &sid, GFP_KERNEL)'),
    ('security_sid_to_context(&fake_state, sid, &canon, &len)',
     'security_sid_to_context(&selinux_state, sid, &canon, &len)'),
    ('security_context_str_to_sid(&fake_state, scon, &ssid, GFP_KERNEL)',
     'security_context_str_to_sid(&selinux_state, scon, &ssid, GFP_KERNEL)'),
    ('security_context_str_to_sid(&fake_state, tcon, &tsid, GFP_KERNEL)',
     'security_context_str_to_sid(&selinux_state, tcon, &tsid, GFP_KERNEL)'),
    ('security_compute_av_user(&fake_state, ssid, tsid, tclass, &avd)',
     'security_compute_av_user(&selinux_state, ssid, tsid, tclass, &avd)'),
]
for old, new in replacements:
    if old in src:
        src = src.replace(old, new)
open(path, 'w').write(src)
result = subprocess.run(['grep', '-n', 'fake_state', path], capture_output=True, text=True)
if result.stdout:
    print(f'[FAIL] fake_state still in {path}')
else:
    print(f'[OK] fake_state -> selinux_state in {path}')
EOF
  done
}

_inject_susfs_init() {
  local KSU_C="$1"
  [ ! -f "$KSU_C" ] && return 0
  grep -q "susfs_init" "$KSU_C" && return 0

  # inject include
  if ! grep -q "#include <linux/susfs.h>" "$KSU_C"; then
    if grep -q '#include "ksu.h"' "$KSU_C"; then
      sed -i '/#include "ksu.h"/a #include <linux\/susfs.h>' "$KSU_C"
    else
      sed -i '1i#include <linux/susfs.h>' "$KSU_C"
    fi
  fi

  # inject susfs_init() — 3 fallback anchors
  if grep -q "ksu_feature_init();" "$KSU_C"; then
    awk '/ksu_feature_init\(\);/{print; printf "#ifdef CONFIG_KSU_SUSFS\n\tsusfs_init();\n#endif\n"; next}1' "$KSU_C" > "$KSU_C.tmp" && mv "$KSU_C.tmp" "$KSU_C"
  elif grep -q "ksu_supercalls_init();" "$KSU_C"; then
    awk '/ksu_supercalls_init\(\);/{printf "#ifdef CONFIG_KSU_SUSFS\n\tsusfs_init();\n#endif\n"; print; next}1' "$KSU_C" > "$KSU_C.tmp" && mv "$KSU_C.tmp" "$KSU_C"
  elif grep -q "ksu_core_init();" "$KSU_C"; then
    awk '/ksu_core_init\(\);/{print; printf "#ifdef CONFIG_KSU_SUSFS\n\tsusfs_init();\n#endif\n"; next}1' "$KSU_C" > "$KSU_C.tmp" && mv "$KSU_C.tmp" "$KSU_C"
  else
    echo "[ERROR] _inject_susfs_init: no anchor found in $KSU_C"; return 1
  fi

  if grep -q "susfs_init" "$KSU_C"; then
    echo "[OK] susfs_init injected into $KSU_C"
  else
    echo "[ERROR] susfs_init injection failed in $KSU_C"; return 1
  fi
}


# KernelSU-Next
_fix_susfs_log_rl_stubs() {
  # susfs4ksu 41da83f added SUSFS_LOGI_RL/LOGE_RL but defined them only when
  # CONFIG_KSU_SUSFS_ENABLE_LOG=y; the !ENABLE_LOG branch has no stubs.
  local F="fs/susfs.c"
  [ -f "$F" ] || return 0
  grep -qE '^#define SUSFS_LOGI_RL\(fmt, \.\.\.\)[[:space:]]*$' "$F" && return 0
  if [ "$(grep -cxF '#define SUSFS_LOGE(fmt, ...) ' "$F")" != 1 ]; then
    echo "[FAIL] _fix_susfs_log_rl_stubs: expected exactly 1 empty SUSFS_LOGE stub in $F"
    return 1
  fi
  sed -i '/^#define SUSFS_LOGE(fmt, \.\.\.) $/a #define SUSFS_LOGI_RL(fmt, ...) \n#define SUSFS_LOGE_RL(fmt, ...) ' "$F"
  echo "[OK] susfs.c: added SUSFS_LOG*_RL stubs"
}

_pin_susfs_lvc() {
  # kernel-release-spoof sets VERSION=6 PATCHLEVEL=12, so susfs took 6.x branches.
  # Pin LINUX_VERSION_CODE in fs/susfs.c and include/linux/susfs.h.
  local F="fs/susfs.c"
  if [ -f "$F" ] && ! grep -q "sapphire: pin LINUX_VERSION_CODE" "$F"; then
    if [ "$(grep -c '^#include "mount.h"$' "$F")" = 1 ]; then
      sed -i '/^#include "mount.h"$/a /* sapphire: pin LINUX_VERSION_CODE to real 5.15.220 (spoofed to 6.12) */\n#undef LINUX_VERSION_CODE\n#define LINUX_VERSION_CODE KERNEL_VERSION(5, 15, 220)' "$F"
      echo "[OK] susfs.c: LINUX_VERSION_CODE pinned to 5.15.220"
    fi
  fi
  local H="include/linux/susfs.h"
  if [ -f "$H" ] && ! grep -q "sapphire: pin LINUX_VERSION_CODE" "$H"; then
    if [ "$(grep -c '^#include <linux/version.h>$' "$H")" = 1 ]; then
      sed -i '/^#include <linux\/version\.h>$/a /* sapphire: pin LINUX_VERSION_CODE to real 5.15.220 (spoofed to 6.12) */\n#undef LINUX_VERSION_CODE\n#define LINUX_VERSION_CODE KERNEL_VERSION(5, 15, 220)' "$H"
      echo "[OK] susfs.h: LINUX_VERSION_CODE pinned to 5.15.220"
    fi
  fi
}

_patch_susfs_def_h() {
  # Latest susfs_def.h calls current_uid() without <linux/cred.h>.
  # Breaks compile mid-file — everything declared after call site is unseen.
  local DEF_H="include/linux/susfs_def.h"
  [ -f "$DEF_H" ] || return 0
  grep -q "linux/cred.h" "$DEF_H" && return 0
  sed -i '1i #include <linux/cred.h>' "$DEF_H"
  echo "[OK] susfs_def.h: added linux/cred.h"
}


_patch_namespace_gki_hunk1() {
  # susfs patch hunk#1 fails on GKI: trace/hooks/blk.h shifts context lines.
  # Manually applies the rejected include + extern decls + CL_COPY_MNT_NS define.
  grep -q "susfs_def.h" fs/namespace.c && return 0
  python3 - <<'EOF'
txt = open("fs/namespace.c").read()
txt = txt.replace(
    "#include <linux/mnt_idmapping.h>",
    "#include <linux/mnt_idmapping.h>\n\n"
    "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
    "#include <linux/susfs_def.h>\n"
    "#endif",
    1
)
txt = txt.replace(
    '#include "internal.h"',
    '#include "internal.h"\n\n'
    "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n"
    "extern bool susfs_is_current_ksu_domain(void);\n"
    "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n\n"
    "#define CL_COPY_MNT_NS BIT(25)\n\n"
    "#endif",
    1
)
open("fs/namespace.c", "w").write(txt)
print("[OK] namespace.c: hunk#1 applied manually")
EOF
}

_fix_ksu_umount_missing_set() {
    # official KernelSU main repo") dropped kernel_umount_feature_set()'s
  # definition but left the struct reference to it -- breaks compile.
  # Still unfixed on builtin HEAD as of 2026-09-04. Self-deactivates once
  # upstream restores the definition (grep guard below).
  local KU_C="$1"
  [ -f "$KU_C" ] || return 0
  grep -q "kernel_umount_feature_set" "$KU_C" || return 0
  grep -q "static int kernel_umount_feature_set" "$KU_C" && return 0
  python3 - "$KU_C" <<'EOF'
import sys
path = sys.argv[1]
txt = open(path).read()
marker = "static int kernel_umount_feature_get(u64 *value)"
idx = txt.find(marker)
if idx == -1:
    print("[WARN] kernel_umount.c: get_handler anchor not found, skipping umount fix")
    sys.exit(0)
end = txt.find("\n}\n", idx) + 3
insert = (
    "\nstatic int kernel_umount_feature_set(u64 value)\n"
    "{\n"
    "    bool enable = value != 0;\n"
    "    ksu_kernel_umount_enabled = enable;\n"
    "    pr_info(\"kernel_umount: set to %d\\n\", enable);\n"
    "    return 0;\n"
    "}\n"
)
txt = txt[:end] + insert + txt[end:]
open(path, "w").write(txt)
print("[OK] kernel_umount.c: restored missing kernel_umount_feature_set")
EOF
}

_fix_susfs_exec_sksu() {
  # ShirkNeko SUSFS patch injects ksu_handle_execveat / ksu_install_su_fd
  # (syscall_event_bridge.c) and never ships these symbols. Strip all
  # CONFIG_KSU_SUSFS blocks from exec.c except the susfs_def.h include.
  # Self-deactivates if exec.c no longer has the markers.
  local EXEC_C="fs/exec.c"
  [ -f "$EXEC_C" ] || return 0
  grep -q "ksu_install_su_fd\|ksu_handle_execveat" "$EXEC_C" || return 0
  python3 - <<PYEOF "$EXEC_C"
import sys, re
path = sys.argv[1]
txt = open(path).read()

txt = re.sub(
    r'#ifdef CONFIG_KSU_SUSFS\nextern struct static_key_true ksu_su_compat_enabled;.*?#endif\n\n',
    '', txt, count=1, flags=re.DOTALL)
txt = re.sub(
    r'#ifdef CONFIG_KSU_SUSFS\n\s*bool is_su_session = false;\n#endif[^\n]*\n',
    '', txt, count=1, flags=re.DOTALL)
txt = re.sub(
    r'#ifdef CONFIG_KSU_SUSFS\n\s*if [(]likely[(]susfs_is_current_proc_no_su.*?#endif\n',
    '', txt, count=1, flags=re.DOTALL)
txt = re.sub(
    r'#ifdef CONFIG_KSU_SUSFS\n\s*if [(]unlikely[(]is_su_session.*?#endif[^\n]*\n',
    '', txt, count=1, flags=re.DOTALL)

open(path, 'w').write(txt)
print("[OK] exec.c: stripped exec.c SUSFS hooks")
PYEOF
}

# Checkout an exact tag/ref in the given dir if a pin override was supplied.
# Hard-fails (not falls back) — this path is only used by the verify gate,
# so a bad pin should surface loudly rather than silently building HEAD.
_checkout_pin() {
  local DIR="$1" PIN="$2" LABEL="$3"
  [ -z "$PIN" ] && return 0
  echo "[PIN] ${LABEL}: checking out ${PIN} (override)"
  git -C "$DIR" checkout -q "$PIN" || {
    echo "[ERROR] ${LABEL}: failed to checkout pinned ref '${PIN}'"; exit 1;
  }
}

_pin_lvc_after() {
  local F="$1" ANCHOR="$2"
  [ -f "$F" ] || { echo "[FAIL] _pin_lvc_after: $F not found"; return 1; }
  if [ "$(grep -cFx -- "$ANCHOR" "$F")" != 1 ]; then
    echo "[FAIL] _pin_lvc_after: expected exactly 1 '$ANCHOR' in $F"
    return 1
  fi
  # skip if pin already exists immediately after this specific anchor
  if grep -A1 -Fx -- "$ANCHOR" "$F" | grep -q "sapphire: pin LINUX_VERSION_CODE"; then
    return 0
  fi
  if [ "$(grep -cFx -- "$ANCHOR" "$F")" != 1 ]; then
    echo "[FAIL] _pin_lvc_after: expected exactly 1 '$ANCHOR' in $F"
    return 1
  fi
  awk -v a="$ANCHOR" '{ print } $0 == a { print "/* sapphire: pin LINUX_VERSION_CODE to real 5.15.220 (spoofed to 6.12) */"; print "#undef LINUX_VERSION_CODE"; print "#define LINUX_VERSION_CODE KERNEL_VERSION(5, 15, 220)" }' "$F" > "$F.sapphire.tmp" \
    && cat "$F.sapphire.tmp" > "$F" && rm -f "$F.sapphire.tmp"
  echo "[OK] $F: LINUX_VERSION_CODE pinned to 5.15.220"
}

_pin_lvc_before() {
  local F="$1" ANCHOR="$2"
  [ -f "$F" ] || { echo "[FAIL] _pin_lvc_before: $F not found"; return 1; }
  if [ "$(grep -cF -- "$ANCHOR" "$F")" != 1 ]; then
    echo "[FAIL] _pin_lvc_before: expected exactly 1 '$ANCHOR' in $F"
    return 1
  fi
  # skip if pin already exists immediately before this specific anchor
  if grep -B1 -F -- "$ANCHOR" "$F" | grep -q "sapphire: pin LINUX_VERSION_CODE"; then
    return 0
  fi
  awk -v a="$ANCHOR" '{ if ($0 == a) { print "/* sapphire: pin LINUX_VERSION_CODE to real 5.15.220 (spoofed to 6.12) */"; print "#undef LINUX_VERSION_CODE"; print "#define LINUX_VERSION_CODE KERNEL_VERSION(5, 15, 220)" } print }' "$F" > "$F.sapphire.tmp" \
    && cat "$F.sapphire.tmp" > "$F" && rm -f "$F.sapphire.tmp"
  echo "[OK] $F: LINUX_VERSION_CODE pinned before '$ANCHOR'"
}

_pin_sksu_lvc() {
  # SukiSU-Ultra/builtin unity build: ksu_main.c includes all .c files directly.
  # kernel-release-spoof sets VERSION=6 PATCHLEVEL=12.
  # Any include of <linux/version.h> resets LINUX_VERSION_CODE to 6.12.
  # Pin LINUX_VERSION_CODE to 5.15.220 immediately after every <linux/version.h>
  # include in the SukiSU-Ultra tree so the entire unity build stays on 5.15.
  _pin_lvc_after "SukiSU-Ultra/kernel/kernel_includes.h" '#include <linux/version.h>' || return 1
  _pin_lvc_before "SukiSU-Ultra/kernel/kernel_includes.h" '// versioned / conditional' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/kernel_includes.h" '#include <linux/lsm_hooks.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/include/arch.h" '#include <linux/version.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/manager/pkg_observer_compat.h" '#include <linux/version.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/extension/dynamic_sig_fallback.c" '#include <linux/version.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/extension/cpu_spoof.c" '#include <linux/version.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/extension/kpm/compact.c" '#include "compact.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/extension/kpm/super_access.c" '#include <linux/kprobes.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/feature/mount_hide.c" '#include <linux/types.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/feature/selinux_hide.c" '#include "objsec.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/infra/symbol_resolver.c" '#include "infra/symbol_resolver.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/preinit/preinit.c" '#include <linux/version.h>' || return 1
}

_pin_ksun_lvc() {
  # KernelSU-Next takes the 6.12 LSM static_call path under the release spoof.
  _pin_lvc_after "KernelSU-Next/kernel/hook/lsm_hook.h" '#include <linux/version.h>' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/hook/lsm_hook.c" '#include "klog.h" // IWYU pragma: keep' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/infra/file_wrapper.c" '#include "infra/file_wrapper.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/extras.c" '#include "arch.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/feature/selinux_hide.c" '#include "hook/lsm_hook.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/infra/seccomp_cache.c" '#include "infra/seccomp_cache.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/infra/symbol_resolver.c" '#include "infra/symbol_resolver.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/manager/apk_sign.c" '#include <linux/version.h>' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/manager/pkg_observer.c" '#include "manager/throne_tracker.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/manager/throne_tracker.c" '#include "manager/throne_tracker.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/policy/app_profile.c" '#include "hook/tp_marker.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/selinux/rules.c" '#include "xfrm.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/selinux/sepolicy.c" '#include "ss/symtab.h"' || return 1
  _pin_lvc_after "KernelSU-Next/kernel/compat/samsung_kdp.c" '#include <linux/version.h>' || return 1
}

if [ "$KSU_TYPE" = "ksun" ]; then
  rm -rf ./KernelSU ./drivers/kernelsu ./KernelSU-Next
  curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh" \
    | bash -s dev-susfs
  [ -d "KernelSU-Next" ] || { echo "[ERROR] KernelSU-Next not found"; exit 1; }

  cd KernelSU-Next
  git fetch --tags 2>/dev/null || true
  _checkout_pin "." "${KSUN_TAG_PIN:-}" "KSU-Next"
  KSUN_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
  KSUN_SHA=$(git rev-parse HEAD)
  echo "KSUN_TAG=$KSUN_TAG"    >> "${GITHUB_ENV:-/dev/null}"
  echo "KSUN_SHA=$KSUN_SHA"    >> "${GITHUB_ENV:-/dev/null}"
  echo "$KSUN_TAG"                  > "$WORK_DIR/ksun_tag.txt"
  echo "$KSUN_SHA"                  > "$WORK_DIR/ksun_sha.txt"
  _ksun_ver=$(grep -rh "^#define KSU_VERSION\b" kernel/ 2>/dev/null \
  | awk 'NR==1{print $NF}' | tr -d '[:space:]')
  echo "${_ksun_ver:-}" > "$WORK_DIR/ksun_version.txt"
  cd ..

  # SUSFS — simonpunk main branch (compatible with KSU-Next)
  git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android13-5.15
  SUSFS_COMMIT=$(git -C susfs4ksu rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "SUSFS_COMMIT=$SUSFS_COMMIT" >> "${GITHUB_ENV:-/dev/null}"
  echo "[OK] SUSFS commit: $SUSFS_COMMIT"

  SUSFS_PATCH="susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
  [ -f "$SUSFS_PATCH" ] && patch -p1 --forward --batch --fuzz=3 < "$SUSFS_PATCH" || true
  _patch_namespace_gki_hunk1
  mkdir -p fs include/linux
  cp -f susfs4ksu/kernel_patches/fs/*            fs/
  cp -f susfs4ksu/kernel_patches/include/linux/* include/linux/
  _patch_susfs_def_h
  _pin_susfs_lvc
  _fix_susfs_log_rl_stubs || exit 1
  _pin_ksun_lvc
  _fix_susfs_fake_state

  _inject_susfs_init "KernelSU-Next/kernel/ksu.c"
  _link_ksu_driver "KernelSU-Next"
  rm -rf susfs4ksu


elif [ "$KSU_TYPE" = "sksu" ]; then
  rm -rf ./KernelSU ./drivers/kernelsu ./SukiSU-Ultra

  git clone --depth=1 --branch "${SKSU_TAG_PIN:-builtin}" \
    https://github.com/SukiSU-Ultra/SukiSU-Ultra.git
  [ -d "SukiSU-Ultra" ] || { echo "[ERROR] SukiSU-Ultra not found"; exit 1; }

  cd SukiSU-Ultra
  git fetch --tags 2>/dev/null || true
  SKSU_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null | tr -d '[:space:]')
  SKSU_TAG=${SKSU_TAG:-$(git describe --tags --abbrev=0 HEAD 2>/dev/null | tr -d '[:space:]')}
  SKSU_TAG=${SKSU_TAG:-unknown}
  SKSU_SHA=$(git rev-parse HEAD)
  echo "SKSU_TAG=$SKSU_TAG"  >> "${GITHUB_ENV:-/dev/null}"
  echo "SKSU_SHA=$SKSU_SHA"  >> "${GITHUB_ENV:-/dev/null}"
  echo "$SKSU_TAG"                > "$WORK_DIR/sksu_tag.txt"
  echo "$SKSU_SHA"                > "$WORK_DIR/sksu_sha.txt"
  _sksu_ver=$(grep -rh "^#define KSU_VERSION\b" kernel/ 2>/dev/null \
    | awk 'NR==1{print $NF}' | tr -d '[:space:]')
  echo "${_sksu_ver:-builtin}" > "$WORK_DIR/sksu_version.txt"
  cd ..

  # Apply SUSFS to kernel tree; SukiSU builtin branch has native SUSFS support
  git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git

  SUSFS_COMMIT=$(git -C susfs4ksu rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "SUSFS_COMMIT=$SUSFS_COMMIT" >> "${GITHUB_ENV:-/dev/null}"
  echo "[OK] SUSFS commit: $SUSFS_COMMIT"

  SUSFS_PATCH="susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
  [ -f "$SUSFS_PATCH" ] && patch -p1 --forward --batch --fuzz=3 < "$SUSFS_PATCH" || true
  _patch_namespace_gki_hunk1
  mkdir -p fs include/linux
  cp -f susfs4ksu/kernel_patches/fs/*            fs/
  cp -f susfs4ksu/kernel_patches/include/linux/* include/linux/
  _patch_susfs_def_h
  _pin_susfs_lvc
  _fix_susfs_log_rl_stubs || exit 1

  _pin_sksu_lvc || exit 1
  _link_ksu_driver "SukiSU-Ultra/kernel"
  rm -rf susfs4ksu

fi

echo "[OK] KSU setup complete: $KSU_TYPE"
