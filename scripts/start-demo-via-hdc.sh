#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/.." && pwd)

bundle_name=io.github.neptune.sdk.harmony
ability_name=EntryAbility
callback_port=${HDC_CALLBACK_PORT:-28767}
gateway_port=${HDC_GATEWAY_PORT:-18765}
target=${HDC_TARGET:-}
hap_path=${HDC_HAP_PATH:-}
keep_awake_ms=${HDC_KEEP_AWAKE_MS:-600000}
unlock_swipe=${HDC_UNLOCK_SWIPE:-"500 1800 500 300"}
skip_build=0
skip_unlock=0
timeout_overridden=0

log() {
  printf '%s\n' "[start-demo-via-hdc] $*" >&2
}

die() {
  log "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/start-demo-via-hdc.sh [options] [hap-path]

Options:
  --target <connect-key>    Target device key to use.
  --hap <path>              Demo HAP path.
  --bundle <bundle-name>    Bundle name to start.
  --ability <ability-name>  Ability name to start.
  --keep-awake-ms <ms>      Screen-off override during launch.
  --unlock-swipe "x1 y1 x2 y2"
                            Swipe coordinates used for best-effort unlock.
  --no-build                Do not auto-build the demo HAP when missing.
  --no-unlock               Skip wake/unlock attempts.
  -h, --help                Show this help text.

Environment:
  HDC_TARGET
  HDC_HAP_PATH
  HDC_KEEP_AWAKE_MS
  HDC_UNLOCK_SWIPE
EOF
}

normalize_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)
      dir=$(CDPATH= cd -- "$(dirname "$1")" && pwd)
      printf '%s\n' "${dir}/$(basename "$1")"
      ;;
  esac
}

find_demo_hap() {
  candidate=""
  for path in \
    "${repo_root}/entry/build/default/outputs/default/entry-default-unsigned.hap" \
    "${repo_root}/entry/build/default/outputs/default/entry-default-signed.hap"
  do
    if [ -f "$path" ]; then
      candidate=$path
      break
    fi
  done

  if [ -z "$candidate" ] && [ "$skip_build" -eq 0 ]; then
    log "No built HAP found. Building entry demo first..."
    "${repo_root}/scripts/build-demo-entry.sh"
    for path in \
      "${repo_root}/entry/build/default/outputs/default/entry-default-unsigned.hap" \
      "${repo_root}/entry/build/default/outputs/default/entry-default-signed.hap"
    do
      if [ -f "$path" ]; then
        candidate=$path
        break
      fi
    done
  fi

  if [ -z "$candidate" ]; then
    die "Demo HAP not found. Build it first with ./scripts/build-demo-entry.sh"
  fi

  printf '%s\n' "$candidate"
}

resolve_target() {
  if [ -n "$target" ]; then
    return
  fi

  if [ -n "${HDC_TARGET:-}" ]; then
    target=$HDC_TARGET
    return
  fi

  connected_targets=$(
    hdc list targets -v | awk 'NF >= 3 && $3 == "Connected" { print $1 }'
  )

  connected_count=$(printf '%s\n' "$connected_targets" | sed '/^$/d' | wc -l | tr -d ' ')

  case "$connected_count" in
    0)
      die "No connected HDC target found. Run DevEco Studio or set HDC_TARGET."
      ;;
    1)
      target=$(printf '%s\n' "$connected_targets" | sed '/^$/d' | head -n 1)
      ;;
    *)
      log "Multiple connected targets detected:"
      printf '%s\n' "$connected_targets" | sed '/^$/d' >&2
      die "Set --target or HDC_TARGET to pick one target."
      ;;
  esac
}

hdc_exec() {
  if [ -n "$target" ]; then
    hdc -t "$target" "$@"
  else
    hdc "$@"
  fi
}

attempt_unlock() {
  if [ "$skip_unlock" -eq 1 ]; then
    return
  fi

  log "Best-effort wakeup..."
  if hdc_exec shell power-shell timeout -o "$keep_awake_ms" >/dev/null 2>&1; then
    timeout_overridden=1
  fi
  hdc_exec shell power-shell wakeup >/dev/null 2>&1 || true
  sleep 1

  set -- $unlock_swipe
  if [ $# -ge 4 ]; then
    log "Best-effort unlock swipe: $1 $2 $3 $4"
    hdc_exec shell uinput swipe "$1" "$2" "$3" "$4" >/dev/null 2>&1 || true
    sleep 1
  else
    log "HDC_UNLOCK_SWIPE needs 4 numbers; skip swipe step."
  fi
}

restore_timeout() {
  if [ "$timeout_overridden" -eq 1 ]; then
    hdc_exec shell power-shell timeout -r >/dev/null 2>&1 || true
  fi
}

print_manual_steps() {
  cat >&2 <<'EOF'
Automatic unlock did not clear the lock screen.
Manual steps:
1. Wake and unlock the simulator screen.
2. Swipe up once from the bottom of the screen.
3. Press Enter here to retry.
EOF
}

start_demo() {
  launch_output=$(hdc_exec shell aa start -b "$bundle_name" -a "$ability_name" -W 2>&1 || true)
  printf '%s\n' "$launch_output"

  if printf '%s\n' "$launch_output" | grep -qi 'screen locked during launch'; then
    return 2
  fi

  if printf '%s\n' "$launch_output" | grep -qi 'start ability successfully'; then
    return 0
  fi

  return 1
}

verify_foreground() {
  i=1
  while [ "$i" -le 3 ]; do
    dump_output=$(hdc_exec shell aa dump -l "$ability_name" 2>&1 || true)
    printf '%s\n' "$dump_output"

    if printf '%s\n' "$dump_output" | grep -q 'state #FOREGROUND'; then
      return 0
    fi

    sleep 1
    i=$((i + 1))
  done

  return 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die "--target requires a value"
      target=$2
      shift 2
      ;;
    --hap)
      [ $# -ge 2 ] || die "--hap requires a value"
      hap_path=$2
      shift 2
      ;;
    --bundle)
      [ $# -ge 2 ] || die "--bundle requires a value"
      bundle_name=$2
      shift 2
      ;;
    --ability)
      [ $# -ge 2 ] || die "--ability requires a value"
      ability_name=$2
      shift 2
      ;;
    --keep-awake-ms)
      [ $# -ge 2 ] || die "--keep-awake-ms requires a value"
      keep_awake_ms=$2
      shift 2
      ;;
    --unlock-swipe)
      [ $# -ge 2 ] || die "--unlock-swipe requires a value"
      unlock_swipe=$2
      shift 2
      ;;
    --no-build)
      skip_build=1
      shift
      ;;
    --no-unlock)
      skip_unlock=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "$hap_path" ] && [ -f "$1" ]; then
        hap_path=$1
        shift
      else
        die "Unknown argument: $1"
      fi
      ;;
  esac
done

resolve_target

if [ -z "$hap_path" ]; then
  hap_path=$(find_demo_hap)
fi

hap_path=$(normalize_path "$hap_path")
[ -f "$hap_path" ] || die "HAP not found: $hap_path"

trap restore_timeout EXIT INT TERM HUP QUIT

log "Target: $target"
log "Bundle: $bundle_name"
log "Ability: $ability_name"
log "HAP: $hap_path"
log "Preparing host->device fport tcp:${callback_port} -> tcp:${callback_port}..."
if ! hdc_exec fport "tcp:${callback_port}" "tcp:${callback_port}" >/dev/null 2>&1; then
  log "fport setup skipped (it may already exist): tcp:${callback_port}"
fi
log "Preparing device->host rport tcp:${gateway_port} -> tcp:${gateway_port}..."
if ! hdc_exec rport "tcp:${gateway_port}" "tcp:${gateway_port}" >/dev/null 2>&1; then
  log "rport setup skipped (it may already exist): tcp:${gateway_port}"
fi

attempt_unlock

log "Installing HAP..."
if install_output=$(hdc_exec install -r "$hap_path" 2>&1); then
  install_rc=0
else
  install_rc=$?
fi
printf '%s\n' "$install_output"

if [ "$install_rc" -ne 0 ] || printf '%s\n' "$install_output" | grep -qiE 'fail|error'; then
  die "HAP install failed"
fi

attempt=1
while [ "$attempt" -le 2 ]; do
  log "Launching demo ability (attempt $attempt)..."
  if [ "$attempt" -gt 1 ]; then
    attempt_unlock
  fi

  if start_demo; then
    launch_rc=0
  else
    launch_rc=$?
  fi

  if [ "$launch_rc" -eq 0 ]; then
    if verify_foreground; then
      log "Result: demo ability is in foreground."
      exit 0
    fi
    log "Warning: aa start succeeded, but foreground state was not confirmed immediately."
    exit 0
  fi

  if [ "$launch_rc" -eq 2 ]; then
    print_manual_steps
    if [ -t 0 ]; then
      printf 'Press Enter after unlocking to retry: ' >&2
      IFS= read -r _
      attempt=$((attempt + 1))
      continue
    fi
    die "stdin is not a terminal; cannot wait for manual confirmation."
  fi

  if [ "$attempt" -eq 1 ]; then
    log "Launch failed once; trying one unlock-and-retry cycle."
    attempt=$((attempt + 1))
    continue
  fi

  die "Launch failed after retry."
done
