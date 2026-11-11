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
  # kernel-release-spoof sets VERSION=6 PATCHLEVEL=12, so susfs.c took 6.x branches.
  # Pin LINUX_VERSION_CODE after the last include, same pattern as nomount.h.
  local F="fs/susfs.c"
  [ -f "$F" ] || return 0
  grep -q "sapphire: pin LINUX_VERSION_CODE" "$F" && return 0
  if [ "$(grep -c '^#include "mount.h"$' "$F")" != 1 ]; then
    echo "[FAIL] _pin_susfs_lvc: expected exactly 1 mount.h include in $F"
    return 1
  fi
  sed -i '/^#include "mount.h"$/a /* sapphire: pin LINUX_VERSION_CODE to real 5.15.220 (spoofed to 6.12) */\n#undef LINUX_VERSION_CODE\n#define LINUX_VERSION_CODE KERNEL_VERSION(5, 15, 220)' "$F"
  echo "[OK] susfs.c: LINUX_VERSION_CODE pinned to 5.15.220"
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

_apply_sksu_susfs_ksu() {
  # v4.3.0-r2 ships without SUSFS. Apply simonpunk's KernelSU enable-patch,
  # then hand-adapt the 5 files that reject:
  #   init.c (4 hunks), setuid_hook.c (1), allowlist.c (1),
  #   ksud_integration.c (1)
  #   rules.c applies clean on main branch
  # dispatch.c now applies clean — no hand-adapt needed.
  local D="SukiSU-Ultra"
  local P="susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  [ -f "$P" ] || { echo "[FAIL] _apply_sksu_susfs_ksu: $P not found"; return 1; }
  [ -d "$D/kernel" ] || { echo "[FAIL] _apply_sksu_susfs_ksu: $D/kernel not found"; return 1; }
  (
    cd "$D" || exit 1
    patch -p1 --forward --no-backup-if-mismatch < "../$P" > /tmp/sksu_susfs_patch.log 2>&1 || true
    rejs=$(find . -name '*.rej' | sort | tr '\n' ' ')
    expected="./kernel/core/init.c.rej ./kernel/hook/setuid_hook.c.rej ./kernel/policy/allowlist.c.rej ./kernel/runtime/ksud_integration.c.rej "
    if [ "$rejs" != "$expected" ]; then
      echo "[FAIL] unexpected reject set: '$rejs'"
      grep -E 'FAILED|^checking file|^patching file' /tmp/sksu_susfs_patch.log
      exit 1
    fi

    # --- init.c ---
    python3 - <<'INNER'
p = "kernel/core/init.c"
t = open(p).read()
def sub(t, old, new, label):
    n = t.count(old)
    assert n == 1, f"[FAIL] init.c anchor matched {n}x: {label}"
    return t.replace(old, new)

# hunk3: remove syscall_hook.h, add setuid_hook.h + sucompat.h
t = sub(t,
    '#include "selinux/selinux.h"\n#include "hook/syscall_hook.h"\n#include "feature/adb_root.h"\n',
    '#include "selinux/selinux.h"\n#include "feature/adb_root.h"\n#include "hook/setuid_hook.h"\n#include "feature/sucompat.h"\n',
    "hunk3: includes")

# hunk5: remove ksu_bundled and ksu_late_loaded assignment blocks
t = sub(t,
    '\n#ifdef MODULE\nbool ksu_bundled = false;\nmodule_param_named(bundled, ksu_bundled, bool, 0);\n#endif\n\n',
    '\n',
    "hunk5: ksu_bundled")

t = sub(t,
    '\n#ifdef MODULE\n    ksu_late_loaded = (current->pid != 1);\n#else\n    ksu_late_loaded = false;\n#endif\n\n',
    '\n',
    "hunk5: ksu_late_loaded")

# hunk7a: remove syscall_hook_init, inject susfs_init
t = sub(t,
    '    ksu_syscall_hook_init();\n\n    ksu_feature_init();\n',
    '#ifdef CONFIG_KSU_SUSFS\n    susfs_init();\n#endif // #ifdef KSU_SUSFS\n\n    ksu_feature_init();\n',
    "hunk7a: syscall_hook_init -> susfs_init")

# hunk7b: flatten init sequence (remove late_loaded branch)
old7b = (
    "    ksu_sulog_init();\n"
    "    ksu_adb_root_init();\n"
    "    ksu_lsm_hook_init();\n"
    "    ksu_selinux_hide_init();\n"
    "    ksu_avc_spoof_init();\n"
    "    ksu_shell_su_adb_only_init();\n"
    "\n"
    "    ksu_supercalls_init();\n"
    "    ksu_app_profile_init();\n"
    "    ksu_extension_init();\n"
    "    ksu_extension_register_all();\n"
    "\n"
    "    if (ksu_late_loaded) {\n"
    "        pr_info(\"late load mode, skipping kprobe hooks\\n\");\n"
    "\n"
    "        apply_kernelsu_rules();\n"
    "        cache_sid();\n"
    "        setup_ksu_cred();\n"
    "\n"
    "        // Grant current process (ksud late-load) root\n"
    "        // with KSU SELinux domain before enforcing SELinux, so it\n"
    "        // can continue to access /data/app etc. after enforcement.\n"
    "        escape_to_root_for_init();\n"
    "\n"
    "        ksu_allowlist_init();\n"
    "        ksu_load_allow_list();\n"
    "        ksu_dynamic_manager_load();\n"
    "\n"
    "        ksu_syscall_hook_manager_init();\n"
    "\n"
    "        ksu_throne_tracker_init();\n"
    "        ksu_observer_init();\n"
    "        ksu_file_wrapper_init();\n"
    "\n"
    "        ksu_boot_completed = true;\n"
    "        track_throne(false);\n"
    "\n"
    "        ksu_avc_spoof_late_init();\n"
    "        ksu_feature_apply_forced();\n"
    "        ksu_extension_apply_forced();\n"
    "\n"
    "        if (!getenforce()) {\n"
    "            pr_info(\"Permissive SELinux, enforcing\\n\");\n"
    "            setenforce(true);\n"
    "        }\n"
    "\n"
    "    } else {\n"
    "        ksu_syscall_hook_manager_init();\n"
    "\n"
    "        ksu_allowlist_init();\n"
    "\n"
    "        ksu_throne_tracker_init();\n"
    "\n"
    "        ksu_ksud_init();\n"
    "\n"
    "        ksu_preinit_init();\n"
    "\n"
    "        ksu_file_wrapper_init();\n"
    "    }\n"
    "\n"
    "#ifdef MODULE\n"
    "#ifndef CONFIG_KSU_DEBUG\n"
    "    kobject_del(&THIS_MODULE->mkobj.kobj);\n"
    "#endif\n"
    "#endif\n"
)
new7b = (
    "    ksu_supercalls_init();\n"
    "\n"
    "    ksu_sucompat_init();\n"
    "\n"
    "    ksu_setuid_hook_init();\n"
    "\n"
    "    ksu_sulog_init();\n"
    "\n"
    "    ksu_adb_root_init();\n"
    "\n"
    "    ksu_selinux_hide_init();\n"
    "\n"
    "    ksu_shell_su_adb_only_init();\n"
    "\n"
    "    ksu_allowlist_init();\n"
    "\n"
    "    ksu_throne_tracker_init();\n"
    "\n"
    "    ksu_ksud_init();\n"
    "\n"
    "    ksu_preinit_init();\n"
    "\n"
    "    ksu_file_wrapper_init();\n"
    "\n"
)
t = sub(t, old7b, new7b, "hunk7b: flatten init")

# hunk8: flatten exit
t = sub(t,
    "    // Phase 1: Stop all hooks first to prevent new callbacks\n"
    "    ksu_syscall_hook_manager_exit();\n"
    "\n"
    "    ksu_supercalls_exit();\n"
    "\n"
    "    if (!ksu_late_loaded) {\n"
    "        ksu_ksud_exit();\n"
    "        ksu_preinit_exit();\n"
    "    }\n",
    "    ksu_supercalls_exit();\n"
    "\n"
    "    ksu_ksud_exit();\n"
    "\n"
    "    ksu_preinit_exit();\n",
    "hunk8: flatten exit")

# hunk8b: remove ksu_lsm_hook_exit (lsm_hook removed from init, exit must match)
t = sub(t,
    "    ksu_lsm_hook_exit();\n",
    "",
    "hunk8b: ksu_lsm_hook_exit")

open(p, "w").write(t)
print("[OK] init.c adapted")
INNER

    # --- setuid_hook.c ---
    python3 - <<'INNER'
import sys
p = "kernel/hook/setuid_hook.c"
t = open(p).read()

def sub(t, old, new, label):
    n = t.count(old)
    assert n == 1, f"[FAIL] {label}: {n}x"
    return t.replace(old, new)

t = sub(t, '#include "hook/tp_marker.h"\n', '', "tp_marker strip")

old_body = (
    '#include "feature/mount_hide.h"\n'
    '\n'
    'int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid)\n'
    '{\n'
    '    // we rely on the fact that zygote always call setresuid(3) with same uids\n'
    '\n'
    '    if (unlikely(is_uid_manager(new_uid))) {\n'
    '        spin_lock_irq(&current->sighand->siglock);\n'
    '        ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);\n'
    '        ksu_set_task_tracepoint_flag(current);\n'
    '        spin_unlock_irq(&current->sighand->siglock);\n'
    '\n'
    '        ksu_install_fd();\n'
    '        return 0;\n'
    '    }\n'
    '\n'
    '    if (ksu_is_allow_uid_for_current(new_uid)) {\n'
    '        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter) {\n'
    '            spin_lock_irq(&current->sighand->siglock);\n'
    '            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);\n'
    '            spin_unlock_irq(&current->sighand->siglock);\n'
    '        }\n'
    '        ksu_set_task_tracepoint_flag(current);\n'
    '    } else {\n'
    '        ksu_clear_task_tracepoint_flag_if_needed(current);\n'
    '    }\n'
    '\n'
    '    // Handle kernel umount\n'
    '    ksu_handle_umount(old_uid, new_uid);\n'
    '\n'
    '    return 0;\n'
    '}\n'
)
new_body = (
    '#include "feature/mount_hide.h"\n'
    '\n'
    'extern u32 susfs_zygote_sid;\n'
    'extern u32 susfs_zygote_next_sid;\n'
    'extern void disable_seccomp(void);\n'
    'extern struct work_struct susfs_extra_works;\n'
    '\n'
    'static inline void ksu_handle_extra_susfs_work(void)\n'
    '{\n'
    '    if (work_pending(&susfs_extra_works))\n'
    '        return;\n'
    '    schedule_work(&susfs_extra_works);\n'
    '}\n'
    '\n'
    'static int handle_zygote_setresuid(uid_t ruid) {\n'
    '    if (is_isolated_process(ruid)) {\n'
    '        susfs_set_current_proc_no_su();\n'
    '        susfs_set_current_proc_umounted();\n'
    '        goto do_umount;\n'
    '    }\n'
    '    if (likely(ksu_is_manager_appid_valid()) && unlikely(is_uid_manager(ruid))) {\n'
    '        disable_seccomp();\n'
    '        pr_info("install fd for manager: %d\\n", ruid);\n'
    '        ksu_install_fd();\n'
    '        return 0;\n'
    '    }\n'
    '    if (likely(is_appuid(ruid) && ksu_uid_should_umount(ruid))) {\n'
    '        susfs_set_current_proc_no_su();\n'
    '        susfs_set_current_proc_umounted();\n'
    '        goto do_umount;\n'
    '    }\n'
    '    if (ksu_is_allow_uid_for_current(ruid)) {\n'
    '        disable_seccomp();\n'
    '        return 0;\n'
    '    }\n'
    '    susfs_set_current_proc_no_su();\n'
    '    return 0;\n'
    'do_umount:\n'
    '    {\n'
    '        ksu_handle_umount(current_uid().val, ruid);\n'
    '        ksu_handle_extra_susfs_work();\n'
    '    }\n'
    '    return 0;\n'
    '}\n'
    '\n'
    'static int handle_zygote_next_setresuid(uid_t ruid) {\n'
    '    if (is_isolated_process(ruid)) {\n'
    '        susfs_set_current_proc_no_su();\n'
    '        susfs_set_current_proc_umounted();\n'
    '        susfs_set_current_proc_umounted_for_zygote_next();\n'
    '        goto do_susfs_work;\n'
    '    }\n'
    '    if (likely(ksu_is_manager_appid_valid()) && unlikely(is_uid_manager(ruid))) {\n'
    '        disable_seccomp();\n'
    '        pr_info("install fd for manager: %d\\n", ruid);\n'
    '        ksu_install_fd();\n'
    '        return 0;\n'
    '    }\n'
    '    if (likely(is_appuid(ruid) && ksu_uid_should_umount(ruid))) {\n'
    '        susfs_set_current_proc_no_su();\n'
    '        susfs_set_current_proc_umounted();\n'
    '        susfs_set_current_proc_umounted_for_zygote_next();\n'
    '        goto do_susfs_work;\n'
    '    }\n'
    '    if (ksu_is_allow_uid_for_current(ruid)) {\n'
    '        disable_seccomp();\n'
    '        return 0;\n'
    '    }\n'
    '    susfs_set_current_proc_no_su();\n'
    '    return 0;\n'
    'do_susfs_work:\n'
    '    {\n'
    '        ksu_handle_extra_susfs_work();\n'
    '    }\n'
    '    return 0;\n'
    '}\n'
    '\n'
    'int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)\n'
    '{\n'
    '    uid_t cur_uid = current_uid().val;\n'
    '    if (cur_uid != 0)\n'
    '        return 0;\n'
    '    if (susfs_is_sid_equal(current_cred(), susfs_zygote_sid))\n'
    '        return handle_zygote_setresuid(ruid);\n'
    '    if (susfs_is_sid_equal(current_cred(), susfs_zygote_next_sid))\n'
    '        return handle_zygote_next_setresuid(ruid);\n'
    '    return 0;\n'
    '}\n'
)
t = sub(t, old_body, new_body, "setuid_hook body")
open(p, "w").write(t)
print("[OK] setuid_hook.c adapted")
INNER

    # --- allowlist.c ---
    python3 - <<'INNER'
p = "kernel/policy/allowlist.c"
t = open(p).read()
old = ('    if (likely(ksu_is_manager_appid_valid()) && unlikely(ksu_get_manager_appid() == uid % PER_USER_RANGE)) {\n'
       '        // we should not umount on manager!\n'
       '        return false;\n'
       '    }\n')
n = t.count(old)
assert n == 1, f"[FAIL] allowlist.c anchor matched {n}x"
open(p, "w").write(t.replace(old, ""))
print("[OK] allowlist.c adapted")
INNER

    # --- ksud_integration.c ---
    python3 - <<'INNER'
p = "kernel/runtime/ksud_integration.c"
t = open(p).read()
old = ('void ksu_handle_execveat_ksud(const char *path, struct user_arg_ptr *argv)\n'
       '{\n'
       '    static const char app_process[] = "/system/bin/app_process";\n'
       '    static bool first_zygote = true;\n'
       '\n'
       '    /* This applies to versions Android 10+ */\n'
       '    static const char system_bin_init[] = "/system/bin/init";\n'
       '    static bool init_second_stage_executed = false;\n'
       '\n'
       '    // https://cs.android.com/android/platform/superproject/+/android-16.0.0_r2:system/core/init/main.cpp;l=77\n'
       '    if (unlikely(!memcmp(path, system_bin_init, sizeof(system_bin_init) - 1) && argv)) {\n'
       '        char buf[16];\n'
       '        if (!init_second_stage_executed && check_argv(*argv, 1, "second_stage", buf, sizeof(buf))) {\n'
       '            pr_info("/system/bin/init second_stage executed\\n");\n'
       '            ksu_preinit_release();\n'
       '            ksu_selinux_hide_handle_second_stage();\n'
       '            apply_kernelsu_rules();\n'
       '            cache_sid();\n'
       '            setup_ksu_cred();\n'
       '            // after apply_kernelsu_rules, so that selinux_hide has its sepolicy backup\n'
       '            ksu_feature_apply_forced();\n'
       '            // Not earlier: a blocked module failing to load in first stage\n'
       '            // init is fatal, ksuinit uses modules.blocklist for that instead.\n'
       '            ksu_module_blacklist_apply();\n'
       '            init_second_stage_executed = true;\n'
       '        }\n'
       '    }\n'
       '\n'
       '    if (unlikely(first_zygote && !memcmp(path, app_process, sizeof(app_process) - 1) && argv)) {\n'
       '        char buf[16];\n'
       '        if (check_argv(*argv, 1, "-Xzygote", buf, sizeof(buf))) {\n'
       '            pr_info("exec zygote, /data prepared, second_stage: %d\\n", init_second_stage_executed);\n'
       '            ksu_preinit_release();\n'
       '            on_post_fs_data();\n'
       '            first_zygote = false;\n'
       '            ksu_stop_ksud_execve_hook();\n'
       '        }\n'
       '    }\n'
       '}\n')
new = ('extern int ksu_handle_execveat_init(struct filename *filename, struct user_arg_ptr *argv_user, struct user_arg_ptr *envp_user);\n'
       '\n'
       '// IMPORTANT NOTE: the call from execve_handler_pre WON\'T provided correct value for envp and flags in GKI version\n'
       'int ksu_handle_execveat_ksud(int *fd, struct filename **filename_ptr,\n'
       '                             struct user_arg_ptr *argv,\n'
       '                             struct user_arg_ptr *envp, int *flags)\n'
       '{\n'
       '    struct filename *filename;\n'
       '    static const char app_process[] = "/system/bin/app_process";\n'
       '\n'
       '    /* This applies to versions Android 10+ */\n'
       '    static const char system_bin_init[] = "/system/bin/init";\n'
       '\n'
       '    if (!filename_ptr)\n'
       '        return 0;\n'
       '\n'
       '    filename = *filename_ptr;\n'
       '    if (IS_ERR(filename)) {\n'
       '        return 0;\n'
       '    }\n'
       '\n'
       '    if (static_branch_unlikely(&is_init_second_stage_not_executed)) {\n'
       '        // https://cs.android.com/android/platform/superproject/+/android-16.0.0_r2:system/core/init/main.cpp;l=77\n'
       '        if (unlikely(!memcmp(filename->name, system_bin_init, sizeof(system_bin_init) - 1) && argv)) {\n'
       '            char buf[16];\n'
       '            if (check_argv(*argv, 1, "second_stage", buf, sizeof(buf))) {\n'
       '                pr_info("/system/bin/init second_stage executed\\n");\n'
       '                ksu_preinit_release();\n'
       '                ksu_selinux_hide_handle_second_stage();\n'
       '                apply_kernelsu_rules();\n'
       '                cache_sid();\n'
       '                setup_ksu_cred();\n'
       '                // after apply_kernelsu_rules, so that selinux_hide has its sepolicy backup\n'
       '                ksu_feature_apply_forced();\n'
       '                static_branch_disable(&is_init_second_stage_not_executed);\n'
       '            }\n'
       '        }\n'
       '    }\n'
       '\n'
       '    if (static_branch_unlikely(&is_first_zygote)) {\n'
       '        if (unlikely(!memcmp(filename->name, app_process, sizeof(app_process) - 1) && argv)) {\n'
       '            char buf[16];\n'
       '            if (check_argv(*argv, 1, "-Xzygote", buf, sizeof(buf))) {\n'
       '                pr_info("exec zygote, /data prepared, second_stage: %d\\n", !static_key_enabled(&is_init_second_stage_not_executed));\n'
       '                ksu_preinit_release();\n'
       '                on_post_fs_data();\n'
       '                static_branch_disable(&is_first_zygote);\n'
       '            }\n'
       '        }\n'
       '    }\n'
       '\n'
       '    return 0;\n'
       '}\n')
n = t.count(old)
assert n == 1, f"[FAIL] ksud_integration.c anchor matched {n}x"
open(p, "w").write(t.replace(old, new))
print("[OK] ksud_integration.c adapted")
INNER

    # --- rules.c ---
    python3 - <<'INNER'
p = "kernel/selinux/rules.c"
t = open(p).read()
old = ('    pol->latest_granting = old_pol->latest_granting + 1;\n'
       '    rcu_assign_pointer(selinux_state.policy, pol);\n'
       '    synchronize_rcu();\n'
       '    ksu_destroy_sepolicy(old_pol);\n'
       '\n'
       '    reset_avc_cache(pol->latest_granting);\n')
new = ('    rcu_assign_pointer(selinux_state.policy, pol);\n'
       '    synchronize_rcu();\n'
       '    ksu_destroy_sepolicy(old_pol);\n'
       '\n'
       '    reset_avc_cache();\n')
n = t.count(old)
assert n == 1, f"[FAIL] rules.c anchor matched {n}x"
open(p, "w").write(t.replace(old, new))
print("[OK] rules.c adapted")
INNER

    rm -f kernel/core/init.c.rej kernel/hook/setuid_hook.c.rej \
          kernel/policy/allowlist.c.rej kernel/runtime/ksud_integration.c.rej \
          kernel/selinux/rules.c.rej

    if grep -nE 'ksu_syscall_hook_init|ksu_lsm_hook_init|ksu_late_loaded|ksu_bundled' kernel/core/init.c; then
      echo "[FAIL] legacy symbols remain in init.c"; exit 1
    fi
    [ "$(grep -c 'susfs_init();' kernel/core/init.c)" = 1 ] || { echo "[FAIL] susfs_init() count != 1"; exit 1; }
    [ "$(grep -c 'ksu_file_wrapper_init();' kernel/core/init.c)" = 1 ] || { echo "[FAIL] file_wrapper_init count != 1"; exit 1; }
    grep -q 'ksu_handle_execveat_ksud(int \*fd' kernel/runtime/ksud_integration.c || { echo "[FAIL] new execveat signature not found"; exit 1; }
    grep -q '#include "hook/tp_marker.h"' kernel/hook/setuid_hook.c && { echo "[FAIL] tp_marker.h still present"; exit 1; } || true
    grep -q 'reset_avc_cache();' kernel/selinux/rules.c || { echo "[FAIL] reset_avc_cache() not found in rules.c"; exit 1; }
    echo "[OK] SUSFS enable-patch applied to $D"
  ) || return 1
}

_pin_sksu_lvc() {
  # version.h has no include guard: any later include re-defines
  # LINUX_VERSION_CODE (spoofed 6.12) and wipes an earlier pin.
  # So anchor on the LAST include of each file, not the first.
  # app_profile.c / selinux_hide.c: the SUSFS enable-patch drops their
  # tp_marker.h / lsm_hook.h includes, so anchor on the new last include.
  _pin_lvc_after "SukiSU-Ultra/kernel/hook/lsm_hook.h" '#include <linux/version.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/hook/lsm_hook.c" '#include <linux/compiler.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/hook/patch_memory.h" '#include "linux/version.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/infra/file_wrapper.c" '#include "infra/file_wrapper.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/infra/seccomp_cache.c" '#include "infra/seccomp_cache.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/infra/symbol_resolver.c" '#include "infra/symbol_resolver.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/manager/throne_tracker.c" '#include "manager/throne_tracker.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/policy/app_profile.c" '#include "infra/su_mount_ns.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/selinux/rules.c" '#include "xfrm.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/feature/selinux_hide.c" '#include "policy/feature.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/manager/apk_sign.c" '#include <crypto/hash.h>' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/manager/pkg_observer.c" '#include "manager/throne_tracker.h"' || return 1
  _pin_lvc_after "SukiSU-Ultra/kernel/selinux/sepolicy.c" '#include "ss/symtab.h"' || return 1
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
  [ -f "$SUSFS_PATCH" ] && patch -p1 --forward --fuzz=3 < "$SUSFS_PATCH" || true
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

  git clone --depth=1 --branch "${SKSU_TAG_PIN:-main}" \
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
  echo "${_sksu_ver:-}" > "$WORK_DIR/sksu_version.txt"
  cd ..

  # HEAD patches expect KSU preinit, pinned to SKSU_TAG_PIN or v4.3.0-r2; SUSFS floats to HEAD
  git clone -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git

  SUSFS_COMMIT=$(git -C susfs4ksu rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "SUSFS_COMMIT=$SUSFS_COMMIT" >> "${GITHUB_ENV:-/dev/null}"
  echo "[OK] SUSFS commit: $SUSFS_COMMIT"

  SUSFS_PATCH="susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
  [ -f "$SUSFS_PATCH" ] && patch -p1 --forward --fuzz=3 < "$SUSFS_PATCH" || true
  _patch_namespace_gki_hunk1
  mkdir -p fs include/linux
  cp -f susfs4ksu/kernel_patches/fs/*            fs/
  cp -f susfs4ksu/kernel_patches/include/linux/* include/linux/
  _patch_susfs_def_h
  _pin_susfs_lvc

  _apply_sksu_susfs_ksu || exit 1

  # patch_memory.o missing from Kbuild on main branch — add arch-guarded entry
  python3 - <<'INNER'
p = "SukiSU-Ultra/kernel/Kbuild"
t = open(p).read()
if "hook/arm64/patch_memory.o" in t:
    print("[OK] patch_memory.o already in Kbuild")
else:
    old = "kernelsu-objs += hook/setuid_hook.o\n"
    new = ("kernelsu-objs += hook/setuid_hook.o\n"
           "ifeq ($(SRCARCH),arm64)\n"
           "kernelsu-objs += hook/arm64/patch_memory.o\n"
           "endif\n")
    n = t.count(old)
    assert n == 1, f"[FAIL] setuid_hook anchor: {n}x"
    open(p, "w").write(t.replace(old, new))
    print("[OK] hook/arm64/patch_memory.o added to Kbuild")
INNER

  _pin_sksu_lvc
  _link_ksu_driver "SukiSU-Ultra/kernel"
  rm -rf susfs4ksu

fi

echo "[OK] KSU setup complete: $KSU_TYPE"
