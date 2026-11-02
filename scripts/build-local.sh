#!/usr/bin/env bash
# build-local.sh - build the kernel anywhere (pc, droidspaces, arm64 box) with the repo's own CI workflow
# thin launcher: pick source + clang, pick docker or direct, hand over to scripts/local-runner.py
# the runner executes .github/workflows/build-staging.yml itself, so scripts/ and yaml edits apply automatically
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$HOME/seiran-build"
IMAGE_BASE="ubuntu:24.04"
VARIANT="" KSRC_ARG="" CLANG_ARG="" MODE="auto" PLATFORM=""
YES=0 CLEAN=0 NOTIFY=0 NOAPT=0 QUIET=0 DRY=0
MEM_GB="" JOBS="" OUT_DIR=""

usage() {
  cat <<'USAGE'
usage: bash scripts/build-local.sh [options]

  -v, --variant V      ksun | sksu | all | name substring (default: ask)
      --kernel-src D   local kernel git repo to clone from, or "download"
      --clang-dir D    local clang dir (has bin/clang), or "download"
      --root D         work dir (default ~/seiran-build)
      --docker         force docker (ubuntu:24.04)
      --no-docker      run directly on this machine
      --platform P     docker platform (default: linux/amd64 on arm64 hosts)
      --mem GB         assume at most this much RAM when picking jobs (not enforced; the real
                       limit is the container/cgroup limit, e.g. Droidspaces "Limit memory")
      --jobs N         parallel jobs for make (default: from RAM and cpus, 1 GB per job)
      --out D          also copy results to D/<name>-<timestamp> (default: off; results stay in
                       <root>/artifacts/<name>, which the next run of that variant replaces)
      --no-apt         never run apt (deps already installed)
      --notify         send telegram notifications (needs the secrets in env)
      --clean          wipe the work dir first
  -q, --quiet          one line per step, full logs in <root>/logs
  -y, --yes            accept every default prompt
      --dry-run        print the steps that would run, build nothing
  -h, --help           this help

# kernel src / clang: auto-detected, you confirm. nothing found -> pick a path or download.
# a local kernel repo is only a clone seed: committed HEAD is used, your working tree is never touched.
# results: <root>/artifacts/<name>   logs: <root>/logs
USAGE
}

say()  { printf '%s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
die()  { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--variant)   VARIANT="${2:?}"; shift 2 ;;
    --kernel-src)   KSRC_ARG="${2:?}"; shift 2 ;;
    --clang-dir)    CLANG_ARG="${2:?}"; shift 2 ;;
    --root)         ROOT="${2:?}"; shift 2 ;;
    --docker)       MODE=docker; shift ;;
    --no-docker)    MODE=direct; shift ;;
    --platform)     PLATFORM="${2:?}"; shift 2 ;;
    --mem)          MEM_GB="${2:?}"; shift 2 ;;
    --jobs)         JOBS="${2:?}"; shift 2 ;;
    --out)          OUT_DIR="${2:?}"; shift 2 ;;
    --no-apt)       NOAPT=1; shift ;;
    --notify)       NOTIFY=1; shift ;;
    --clean)        CLEAN=1; shift ;;
    -q|--quiet)     QUIET=1; shift ;;
    -y|--yes)       YES=1; shift ;;
    --dry-run)      DRY=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done
ROOT="$(readlink -m "$ROOT")"

# prompts (apt style); non-interactive or -y takes the default
confirm() {
  local def="${2:-Y}" ans
  if [[ $YES == 1 || ! -t 0 ]]; then [[ $def == Y ]]; return; fi
  read -r -p "$1 [$([[ $def == Y ]] && echo Y/n || echo y/N)] " ans || true
  ans="${ans:-$def}"; [[ $ans =~ ^[Yy] ]]
}

# validators
GKI_BRANCH="$(sed -n 's/^ *GKI_BRANCH="\(.*\)"/\1/p' "$REPO/scripts/clone-source.sh" 2>/dev/null | head -1)"
valid_ksrc() {
  [[ -d "$1/.git" && -f "$1/Makefile" && -d "$1/arch/arm64" ]] || return 1
  [[ -z $GKI_BRANCH ]] || git -C "$1" rev-parse -q --verify "refs/heads/$GKI_BRANCH" >/dev/null 2>&1
}
valid_clang() { [[ -x "$1/bin/clang" || -L "$1/bin/clang" ]]; }

detect() { # detect <validator> <glob>...
  local v="$1" d; shift
  for d in "$@"; do [[ -d $d ]] && "$v" "$d" && { readlink -f "$d"; return 0; }; done
  return 1
}

# sets DIR_ANS ("" = download); exits on abort
ask_dir() { # ask_dir <label> <validator>
  local label="$1" v="$2" c p
  DIR_ANS=""
  if [[ ! -t 0 || $YES == 1 ]]; then return 0; fi
  while true; do
    read -r -p "$label: [d]ownload  [p]ath  [a]bort (d): " c || c=a
    case "${c:-d}" in
      d|D) DIR_ANS=""; return 0 ;;
      a|A) die "aborted" ;;
      p|P)
        read -r -p "  path: " p || p=""
        p="$(readlink -f "${p/#\~/$HOME}" 2>/dev/null || true)"
        if [[ -n $p ]] && "$v" "$p"; then DIR_ANS="$p"; return 0; fi
        warn "not usable: ${p:-empty}" ;;
    esac
  done
}

resolve() { # resolve <label> <validator> <arg> <detect-globs...> ; result in DIR_ANS
  local label="$1" v="$2" arg="$3" det; shift 3
  if [[ -n $arg ]]; then
    if [[ $arg == download ]]; then DIR_ANS=""; return 0; fi
    DIR_ANS="$(readlink -f "${arg/#\~/$HOME}" 2>/dev/null || true)"
    if [[ -n $DIR_ANS ]] && "$v" "$DIR_ANS"; then return 0; fi
    warn "$label: '$arg' is not usable"
    [[ -t 0 && $YES == 0 ]] || die "$label: invalid path (use 'download' to fetch it instead)"
    ask_dir "$label" "$v"; return 0
  fi
  if det="$(detect "$v" "$@")"; then
    say "[detect] $label: $det"
    if confirm "Use this?" Y; then DIR_ANS="$det"; else ask_dir "$label" "$v"; fi
  else
    say "[detect] no $label found"
    ask_dir "$label" "$v"
  fi
}

if [[ $CLEAN == 1 ]]; then
  [[ -n $ROOT && $ROOT != / && $ROOT != "$HOME" && $ROOT != "$REPO" ]] || die "refusing to clean '$ROOT'"
  if [[ -d $ROOT ]] && confirm "Wipe $ROOT?" Y; then rm -rf "$ROOT"; say "[OK] wiped $ROOT"; fi
fi

KSRC="" CLANG=""
if [[ $DRY == 0 ]]; then
  resolve "kernel source" valid_ksrc "$KSRC_ARG" "$HOME"/gki-common* "$REPO"/../gki-common*
  KSRC="$DIR_ANS"
  resolve "clang" valid_clang "$CLANG_ARG" "$HOME/neutron-clang" "$HOME"/*clang* "$REPO/../neutron-clang"
  CLANG="$DIR_ANS"
  [[ -n $KSRC ]] && say "[src] kernel: $KSRC (clone seed, $(git -C "$KSRC" log -1 --format='%h' 2>/dev/null))" || say "[src] kernel: download"
  [[ -n $CLANG ]] && say "[src] clang:  $CLANG" || say "[src] clang:  download"
fi

# runner args
RARGS=(--repo "$REPO" --root "$ROOT")
[[ -n $VARIANT ]] && RARGS+=(--variant "$VARIANT")
[[ -n $KSRC ]]    && RARGS+=(--kernel-src "$KSRC")
[[ -n $CLANG ]]   && RARGS+=(--clang-dir "$CLANG")
[[ $NOTIFY == 1 ]] && RARGS+=(--notify)
[[ $NOAPT == 1 ]]  && RARGS+=(--no-apt)
if [[ -n $OUT_DIR ]]; then
  OUT_DIR="$(readlink -m "$OUT_DIR")"
  [[ $DRY == 1 ]] || mkdir -p "$OUT_DIR" || die "cannot create --out dir: $OUT_DIR"
  RARGS+=(--out "$OUT_DIR")
fi
[[ $QUIET == 1 ]]  && RARGS+=(-q)
[[ $YES == 1 ]]    && RARGS+=(-y)
[[ $DRY == 1 ]]    && RARGS+=(--dry-run)

# direct or docker
HOST_ARCH="$(uname -m)"

# resources: RAM = lower of /proc/meminfo and the cgroup limit; cpus = nproc capped by the cgroup quota
[[ -z $MEM_GB || $MEM_GB =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--mem expects GB, e.g. 6 or 4.5"
[[ -z $JOBS || $JOBS =~ ^[1-9][0-9]*$ ]]           || die "--jobs expects a positive integer"
mem_limit_mb() {
  local kb b f m
  kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || true)"
  m=$(( ${kb:-0} / 1024 ))
  for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
    [[ -r $f ]] || continue
    b="$(cat "$f" 2>/dev/null || true)"
    [[ $b =~ ^[0-9]+$ ]] || continue
    (( b < (1 << 50) )) || continue # effectively unlimited
    b=$(( b / 1048576 ))
    if (( m == 0 || b < m )); then m=$b; fi
  done
  echo "$m"
}
cpu_quota() { # whole cpus allowed by the cgroup quota, empty if none
  local q="" p=""
  if [[ -r /sys/fs/cgroup/cpu.max ]]; then read -r q p < /sys/fs/cgroup/cpu.max || true
  elif [[ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]]; then
    q="$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || true)"
    p="$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || true)"
  fi
  if [[ $q =~ ^[0-9]+$ && $p =~ ^[1-9][0-9]*$ ]]; then echo $(( (q + p - 1) / p )); fi
  return 0
}
CPUS="$(nproc 2>/dev/null || echo 1)"
CQ="$(cpu_quota)"
if [[ -n $CQ ]] && (( CQ >= 1 && CQ < CPUS )); then CPUS=$CQ; fi
MEM_MB="$(mem_limit_mb)"
if [[ -n $MEM_GB ]]; then
  WANT_MB="$(awk -v g="$MEM_GB" 'BEGIN{printf "%d", g*1024}')"
  if (( MEM_MB == 0 || WANT_MB < MEM_MB )); then MEM_MB=$WANT_MB; fi
fi
if [[ -z $JOBS ]]; then
  JCAP=$CPUS; if (( CPUS > 2 )); then JCAP=$(( CPUS - 1 )); fi  # leave one cpu for the host
  if (( MEM_MB == 0 )); then JOBS=$JCAP; warn "cannot read RAM size, jobs = $JCAP (use --jobs / --mem)"
  else
    JOBS=$(( (MEM_MB - 1024) / 1024 )) # keep 1 GB for the system, then 1 GB per job
    if (( JOBS < 1 )); then JOBS=1; fi
    if (( JOBS > JCAP )); then JOBS=$JCAP; fi
  fi
fi
# memory preflight: RAM + disk swap must cover the link/BTF peak. it only offers a temporary swap file, never forces one.
# need defaults to 9 GB (heuristic: pahole alone reached ~5 GB RSS before an OOM kill on an 8 GB machine); override: SEIRAN_NEED_GB
meminfo_mb() { local v; v="$(awk -v k="$1:" '$1==k{print $2}' "${SEIRAN_MEMINFO:-/proc/meminfo}" 2>/dev/null || true)"; echo $(( ${v:-0} / 1024 )); }
disk_swap_free_mb() { # zram is RAM-backed, so it is not counted as extra memory
  awk 'NR>1 && $1 !~ /zram/ {f += $3 - $4} END {printf "%d", f / 1024}' "${SEIRAN_SWAPS:-/proc/swaps}" 2>/dev/null || echo 0
}
mem_preflight() {
  local need_mb=$(( ${SEIRAN_NEED_GB:-9} * 1024 )) have_mb avail_mb total_mb lim_mb deficit_mb add_gb
  local parent dir fs free_mb maxadd S="" undo c dq
  local -a cmds
  avail_mb="$(meminfo_mb MemAvailable)"; total_mb="$(meminfo_mb MemTotal)"; lim_mb="$(mem_limit_mb)"
  have_mb=$avail_mb; if (( MEM_MB > 0 && MEM_MB < have_mb )); then have_mb=$MEM_MB; fi
  have_mb=$(( have_mb + $(disk_swap_free_mb) ))
  if (( have_mb >= need_mb )); then
    say "[mem] ok: ${have_mb} MB RAM+swap usable (the build can need ~$(( need_mb / 1024 )) GB)"; return 0
  fi
  warn "[mem] only ${have_mb} MB RAM+swap usable; the build can need ~$(( need_mb / 1024 )) GB (pahole was OOM-killed at ~5 GB RSS on an 8 GB machine)"
  if (( lim_mb + 64 < total_mb )); then
    warn "[mem] a container/cgroup limit (${lim_mb} MB) is below the host RAM: raise that limit (e.g. Droidspaces 'Limit memory'); host swap would not lift it"
    return 0
  fi
  deficit_mb=$(( need_mb - have_mb )); add_gb=$(( (deficit_mb + 1023) / 1024 ))
  parent="$(dirname "$ROOT")"; dir="$parent/.seiran-swap"
  fs="$(findmnt -no FSTYPE -T "$parent" 2>/dev/null || true)"
  free_mb="$(df -Pm "$parent" 2>/dev/null | awk 'NR==2{print $4}')"; free_mb=${free_mb:-0}
  maxadd=$(( free_mb / 1024 - 15 )) # keep 15 GB free for the work dir
  if (( maxadd < 1 )); then warn "[mem] not enough free disk on $parent (${free_mb} MB) for a swap file"; return 0; fi
  if (( add_gb > maxadd )); then add_gb=$maxadd; fi
  case $fs in btrfs|ext4|xfs) ;; *) warn "[mem] no swap file support here for fs '${fs:-unknown}': free memory or add swap by hand"; return 0 ;; esac
  if [[ $EUID != 0 ]]; then command -v sudo >/dev/null 2>&1 || { warn "[mem] needs root or sudo to use swap"; return 0; }; S="sudo"; fi
  if [[ -e $dir/swapfile ]]; then # left by an earlier run: the file survives a reboot, only the swapon is lost
    if grep -qs -F "$dir/swapfile" "${SEIRAN_SWAPS:-/proc/swaps}"; then
      warn "[mem] $dir/swapfile is already active and still not enough: free memory or add swap by hand"; return 0
    fi
    say "[mem] found an inactive swap file: $dir/swapfile"
    if confirm "Reactivate it now?" N; then
      $S swapon --priority 10 "$dir/swapfile" && say "[mem] swap reactivated" || warn "[mem] swapon failed (continuing without it)"
    else
      say "[mem] skipped, continuing without extra swap"
    fi
    return 0
  fi
  if [[ -e $dir ]]; then warn "[mem] $dir exists without a swapfile: remove it by hand"; return 0; fi
  dq="$(printf '%q' "$dir")"
  if [[ $fs == btrfs ]]; then
    cmds=("btrfs subvolume create $dq" "btrfs filesystem mkswapfile --size ${add_gb}g $dq/swapfile" "swapon --priority 10 $dq/swapfile")
    undo="swapoff $dq/swapfile && btrfs subvolume delete $dq"
  else
    cmds=("mkdir -p $dq" "fallocate -l ${add_gb}G $dq/swapfile" "chmod 600 $dq/swapfile" "mkswap $dq/swapfile" "swapon --priority 10 $dq/swapfile")
    undo="swapoff $dq/swapfile && rm -rf $dq"
  fi
  say "[mem] plan: a temporary ${add_gb} GB swap file on $fs (not in fstab: swapon is lost on reboot, the file stays until you remove it):"
  printf '       %s\n' "${cmds[@]}"
  if confirm "Create it now?" N; then
    for c in "${cmds[@]}"; do $S bash -c "$c" || { warn "[mem] failed: $c (continuing without it)"; return 0; }; done
    say "[mem] swap active. remove later: $S bash -c '$undo'"
  else
    say "[mem] skipped, continuing without extra swap"
  fi
  if [[ "$(systemctl is-active graphical.target 2>/dev/null || true)" == active ]]; then
    say "[mem] tip: the desktop typically holds 1-2 GB. over ssh you can stop it for the build: sudo systemctl isolate multi-user.target (unsaved work is lost; undo: sudo systemctl isolate graphical.target)"
  fi
  return 0
}
if [[ $DRY == 0 ]]; then
  say "[host] $HOST_ARCH | ram ${MEM_MB} MB | cpus $CPUS -> jobs $JOBS"
  mem_preflight
fi
have_docker() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }
glibc_old() { # true when host glibc < 2.36 (neutron needs newer)
  local v; v="$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
  [[ -n $v && "$(printf '%s\n2.36\n' "$v" | sort -V | head -1)" != 2.36 ]]
}
clang_runs() { timeout 30 "$CLANG/bin/clang" --version >/dev/null 2>&1; }

if [[ $DRY == 1 ]]; then MODE=direct
elif [[ $MODE == auto ]]; then
  if [[ -n $CLANG ]]; then
    if clang_runs; then MODE=direct; else MODE=docker; why="clang does not run on this host"; fi
  else
    if [[ $HOST_ARCH != x86_64 ]] || glibc_old; then
      MODE=docker; why="downloaded clang needs x86_64 + glibc >= 2.36"
    else MODE=direct; fi
  fi
  [[ $MODE == docker ]] && say "[mode] docker ($why)"
fi

if [[ $MODE == direct ]]; then
  command -v python3 >/dev/null || die "python3 missing"
  python3 -c 'import yaml' 2>/dev/null || die "python3-yaml missing (apt install python3-yaml)"
  say "[mode] direct"
  export OMP_NUM_THREADS="$JOBS" OMP_THREAD_LIMIT="$JOBS" # nproc (used by build.sh -j) honors these
  exec python3 "$REPO/scripts/local-runner.py" "${RARGS[@]}"
fi

# docker
have_docker || die "docker not usable here (docker info failed). install it or use --no-docker on a glibc >= 2.36 x86_64 machine"
# CI is x86_64 and neutron is x86_64 only
[[ -n $PLATFORM ]] || PLATFORM=linux/amd64
if [[ $HOST_ARCH != x86_64 && $PLATFORM == linux/amd64 ]]; then
  warn "emulating x86_64 (qemu) - expect a much slower build"
  ls /proc/sys/fs/binfmt_misc 2>/dev/null | grep -qi x86 || \
    warn "no x86 binfmt handler found. install: docker run --privileged --rm tonistiigi/binfmt --install amd64"
fi
TAG="seiran-local:24.04-r3-${PLATFORM#linux/}" # bump when the package list changes: image_ok only checks the platform
SECOPT=()
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" == Enforcing ]]; then
  # SELinux would deny the container access to the bind mounts (Errno 13); relabeling host dirs (:z/:Z) is more invasive
  SECOPT=(--security-opt label=disable)
  say "[docker] SELinux enforcing: container runs with label=disable"
fi
image_ok() { [[ "$(docker image inspect "$TAG" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null)" == "$PLATFORM" ]]; }
if ! image_ok; then
  # no buildx/BuildKit needed: bootstrap a container of the right platform, then commit it
  say "[docker] building $TAG (one time)"
  docker rmi "$TAG" >/dev/null 2>&1 || true
  docker rm -f seiran-bootstrap >/dev/null 2>&1 || true
  docker pull --platform "$PLATFORM" "$IMAGE_BASE"
  docker run --net=host --platform "$PLATFORM" --name seiran-bootstrap "$IMAGE_BASE" bash -c \
    'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y --no-install-recommends python3 python3-yaml patch git curl ca-certificates tar xz-utils zstd sudo cpio zip unzip lz4 file tree kmod && rm -rf /var/lib/apt/lists/*' \
    || { docker rm -f seiran-bootstrap >/dev/null 2>&1; die "image bootstrap failed"; }
  docker commit seiran-bootstrap "$TAG" >/dev/null
  docker rm seiran-bootstrap >/dev/null
  image_ok || die "$TAG has the wrong platform: $(docker image inspect "$TAG" --format '{{.Os}}/{{.Architecture}}' 2>&1)"
fi
if [[ -n $CLANG && $DRY == 0 ]]; then
  probe_clang() { # host-side timeout: an emulated process can hang so hard that its own timeout never fires
    local rc=0
    docker rm -f seiran-probe >/dev/null 2>&1 || true
    timeout -k 5 "${PROBE_TIMEOUT:-120}" docker run --rm --name seiran-probe "${SECOPT[@]}" --platform "$PLATFORM" -v "$CLANG:$CLANG:ro" "$TAG" \
      timeout -k 5 90 "$CLANG/bin/clang" --version >/dev/null 2>&1 || rc=$?
    docker rm -f seiran-probe >/dev/null 2>&1 || true
    return $rc
  }
  say "[docker] probing clang inside the container"
  if probe_clang; then
    say "[docker] clang ok"
  elif [[ $HOST_ARCH != x86_64 && $PLATFORM == linux/amd64 ]]; then
    warn "clang crashes or hangs under the x86_64 emulator (likely an old qemu: ubuntu jammy ships 6.2)"
    warn "fix: replace the x86_64 binfmt handler with a newer qemu (tonistiigi/binfmt). affects the whole host and resets on reboot"
    if confirm "Run the fix now?" N; then
      docker run --privileged --rm tonistiigi/binfmt --uninstall qemu-x86_64 >/dev/null 2>&1 || true
      docker run --privileged --rm tonistiigi/binfmt --install amd64 >/dev/null
      probe_clang || die "clang still fails after the binfmt update. run: docker run --rm --platform $PLATFORM -v $CLANG:$CLANG:ro $TAG $CLANG/bin/clang --version"
      say "[docker] clang ok after the binfmt update (repeat the fix after every reboot)"
    else
      die "not fixed. run by hand: docker run --privileged --rm tonistiigi/binfmt --uninstall qemu-x86_64 && docker run --privileged --rm tonistiigi/binfmt --install amd64"
    fi
  else
    die "clang does not run inside the container"
  fi
fi
mkdir -p "$ROOT"
MOUNTS=(-v "$REPO:$REPO:ro" -v "$ROOT:$ROOT")
[[ -z $OUT_DIR ]] || MOUNTS+=(-v "$OUT_DIR:$OUT_DIR")
[[ -n $KSRC ]]  && MOUNTS+=(-v "$KSRC:$KSRC:ro")
[[ -n $CLANG ]] && MOUNTS+=(-v "$CLANG:$CLANG:ro")
TTY=(); [[ -t 0 && -t 1 ]] && TTY=(-it)
say "[docker] run $TAG ($PLATFORM)"
exec docker run --rm --init "${TTY[@]}" --net=host --platform "$PLATFORM" \
  "${SECOPT[@]}" -e OMP_NUM_THREADS="$JOBS" -e OMP_THREAD_LIMIT="$JOBS" \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  "${MOUNTS[@]}" -w "$REPO" "$TAG" python3 "$REPO/scripts/local-runner.py" "${RARGS[@]}"
