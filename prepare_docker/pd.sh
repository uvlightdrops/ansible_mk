#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/common.sh"

ALL=0
POD=""
LABEL=""
VERBOSE=0
QUIET=0
DRY_RUN=0
LOG_FILE=""

usage_pd_global_options_extra() {
  cat <<'EOF'
  -a, --all              Run on all pods (default: single target)
  --pod <name>           Single target pod
  --label <selector>     Pod selector (single: first match, all: all matches)
  -v, --verbose          More command output
  -q, --quiet            Less console output
  --log-file <path>      Append output to file
  --dry-run              Print commands, do not execute
  -h, --help             Show help
EOF
}

usage_pd_commands() {
  cat <<'EOF'
Commands:
  check [basic|home|ssh|nodeport]
      Run one specific check (default: basic)

  diagnose [--full] [--crashloops]
      Run all checks sequentially (basic, home, ssh, nodeport)
      --full         also collect detailed diagnostics artifacts
      --crashloops   with --full and -a, include crashloop collector

  assemble [--level pod|rollout|full] [--no-verify]
      pod       pubkey + checks on pod level
      rollout   configmap + rollout + pubkey + checks
      full      node prep + configmap + rollout + pubkey + checks

  down [--level scale-down|soft|resources|namespace|all] [--purge-data] [-y]
      Controlled teardown (single pod without -a, namespace scope with -a)

  up [assemble options]
      assemble + diagnose

  doctor
      diagnose --full --crashloops
EOF
}

usage_pd_examples() {
  cat <<'EOF'
Examples:
  ./prepare_docker/pd.sh --pod wls-managed-1-0 check ssh
  ./prepare_docker/pd.sh check basic --pod wls-admin-0
  ./prepare_docker/pd.sh -a diagnose
  ./prepare_docker/pd.sh -a assemble --level full
  ./prepare_docker/pd.sh -a down --level scale-down -y
EOF
}

usage() {
  cat <<'EOF'
Usage:
  ./prepare_docker/pd.sh [GLOBAL_OPTIONS] <command> [COMMAND_OPTIONS]

Rule:
  - GLOBAL_OPTIONS are accepted before and after <command>
  - COMMAND_OPTIONS go after <command>

Global options:
EOF
  usage_common_options
  usage_pd_global_options_extra
  echo ""
  usage_pd_commands
  echo ""
  usage_pd_examples
}

usage_pd_command() {
  local cmd="$1"
  case "$cmd" in
    check)
      cat <<'EOF'
Command options for `check`:
  basic|home|ssh|nodeport  Run one specific check (default: basic)
EOF
      ;;
    diagnose)
      cat <<'EOF'
Command options for `diagnose`:
  --full         also collect detailed diagnostics artifacts
  --crashloops   with --full and -a, include crashloop collector
EOF
      ;;
    assemble)
      cat <<'EOF'
Command options for `assemble`:
  --level pod|rollout|full   select assembly level (default: pod, or full with -a)
  --no-verify                skip post-assembly diagnose
EOF
      ;;
    down)
      cat <<'EOF'
Command options for `down`:
  --level scale-down|soft|resources|namespace|all
  --purge-data               additionally wipe hostPath data on all minikube nodes
  -y, --yes                  skip confirmation prompt
EOF
      ;;
    up)
      cat <<'EOF'
Command options for `up`:
  (same as `assemble`)
EOF
      ;;
    doctor)
      cat <<'EOF'
Command options for `doctor`:
  (same as `diagnose --full --crashloops`)
EOF
      ;;
  esac
}

ts() { date -u +%Y%m%dT%H%M%SZ; }

log() {
  local msg="$*"
  if [ "$QUIET" -eq 0 ]; then
    echo "$msg"
  fi
  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$msg" >> "$LOG_FILE"
  fi
}

run_cmd() {
  local cmd=("$@")
  if [ "$VERBOSE" -gt 0 ] || [ "$DRY_RUN" -eq 1 ]; then
    log "+ ${cmd[*]}"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ "${cmd[0]}" = "kc" ]; then
    local kc_exec
    kc_exec="$(type -P kc 2>/dev/null || true)"
    if [ -z "$kc_exec" ] && [ -x "$REPO_ROOT/tools/kc" ]; then
      kc_exec="$REPO_ROOT/tools/kc"
    fi
    if [ -z "$kc_exec" ]; then
      echo "ERROR: kc wrapper not found in PATH and $REPO_ROOT/tools/kc is not executable" >&2
      return 127
    fi
    if [ -n "$LOG_FILE" ]; then
      "$kc_exec" "${cmd[@]:1}" 2>&1 | tee -a "$LOG_FILE"
    else
      "$kc_exec" "${cmd[@]:1}"
    fi
  else
    if [ -n "$LOG_FILE" ]; then
      "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
    else
      "${cmd[@]}"
    fi
  fi
}

read -r -a KC_ARR <<<"$KC_CMD"

kc() {
  run_cmd "${KC_ARR[@]}" "$@"
}

resolve_one_pod() {
  if [ -n "$POD" ]; then
    echo "$POD"
    return
  fi
  if [ -n "$LABEL" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "[dry-run] single pod by label skipped" >&2
      return
    fi
    "${KC_ARR[@]}" get pods -n "$NAMESPACE" -l "$LABEL" -o 'jsonpath={.items[0].metadata.name}'
    return
  fi
  echo "ERROR: single-target mode braucht --pod <name> oder --label <selector> (oder nutze -a/--all)" >&2
  exit 2
}

resolve_all_pods() {
  local args=(get pods -n "$NAMESPACE" -o 'jsonpath={.items[*].metadata.name}')
  if [ -n "$LABEL" ]; then
    args=(get pods -n "$NAMESPACE" -l "$LABEL" -o 'jsonpath={.items[*].metadata.name}')
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] pod list skipped" >&2
    return
  fi
  "${KC_ARR[@]}" "${args[@]}"
}

selected_pods() {
  if [ "$ALL" -eq 1 ]; then
    resolve_all_pods
  else
    resolve_one_pod
  fi
}

install_pubkey_one() {
  local pod="$1"
  local pubkey="${PUBKEY_PATH:-${HOME}/.ssh/id_ed25519_docker.pub}"
  if [ ! -f "$pubkey" ]; then
    echo "ERROR: public key not found: $pubkey" >&2
    exit 2
  fi
  log "Install pubkey on pod: $pod"
  kc exec -i -n "$NAMESPACE" "$pod" -- sh -c \
    'mkdir -p /home/docker/.ssh && touch /home/docker/.ssh/authorized_keys && grep -qxF "$(cat /dev/stdin)" /home/docker/.ssh/authorized_keys || cat >> /home/docker/.ssh/authorized_keys' < "$pubkey"
  kc exec -n "$NAMESPACE" "$pod" -- chown -R docker:docker /home/docker || true
  kc exec -n "$NAMESPACE" "$pod" -- chmod 700 /home/docker/.ssh || true
  kc exec -n "$NAMESPACE" "$pod" -- chmod 600 /home/docker/.ssh/authorized_keys || true
}

install_pubkey_selected() {
  local pods
  pods="$(selected_pods)"
  [ -z "$pods" ] && return
  for p in $pods; do
    install_pubkey_one "$p"
  done
}

check_one_basic() {
  local pod="$1"
  log "-- $pod"
  kc describe pod "$pod" -n "$NAMESPACE" || true
}

check_one_home() {
  local pod="$1"
  log "-- $pod"
  kc exec -n "$NAMESPACE" "$pod" -- sh -c 'id || true; ls -ld /home /home/docker /home/docker/.ssh 2>/dev/null || true'
}

check_one_ssh() {
  local pod="$1"
  log "-- $pod"
  kc exec -n "$NAMESPACE" "$pod" -- sh -c 'command -v ssh >/dev/null 2>&1 || true; command -v sshd >/dev/null 2>&1 && pgrep -x sshd >/dev/null && echo SSHD_OK || (echo SSHD_NOT_OK; exit 1)'
}

check_one_nodeport() {
  local pod="$1"
  log "-- $pod (nodeport ssh)"

  # Determine Node IP
  local node_ip
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] nodeport ssh check skipped for $pod"
    return
  fi
  node_ip=$("${KC_ARR[@]}" get nodes -o 'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
  if [ -z "$node_ip" ] && command -v minikube >/dev/null 2>&1; then
    node_ip=$(minikube ip 2>/dev/null || true)
  fi
  if [ -z "$node_ip" ]; then
    log "  SKIP: could not determine node IP"
    return
  fi

  # Look up the NodePort for this pod via its Service (port 22)
  local svc node_port
  svc=$("${KC_ARR[@]}" get svc -n "$NAMESPACE" -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep "$(echo "$pod" | sed 's/-[a-z0-9]*-[a-z0-9]*$//')" | head -n1 || true)
  if [ -z "$svc" ]; then
    # fallback: pick any NodePort svc with port 22
    node_port=$("${KC_ARR[@]}" get svc -n "$NAMESPACE" \
      -o 'jsonpath={range .items[*]}{.spec.ports[?(@.targetPort==22)].nodePort}{"\n"}{end}' 2>/dev/null \
      | head -n1 || true)
  else
    node_port=$("${KC_ARR[@]}" get svc -n "$NAMESPACE" "$svc" \
      -o 'jsonpath={.spec.ports[?(@.port==22)].nodePort}' 2>/dev/null || true)
  fi

  if [ -z "$node_port" ]; then
    log "  SKIP: no NodePort found for $pod"
    return
  fi

  local key="${PRIVKEY_PATH:-${HOME}/.ssh/id_ed25519_docker}"
  local user="${SSH_USER:-docker}"
  local timeout="${CONNECT_TIMEOUT:-5}"
  local ssh_opts=(-o BatchMode=yes -o ConnectTimeout="$timeout" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

  log "  ssh -i $key -p $node_port $user@$node_ip"
  if ssh "${ssh_opts[@]}" -i "$key" -p "$node_port" "$user@$node_ip" 'echo SSH_OK' 2>/dev/null; then
    log "  -> OK ✓"
  else
    log "  -> FAILED ✗"
  fi
}

cmd_check() {
  local kind="${1:-basic}"
  local pods

  log "== check ($kind)"
  kc get nodes -o wide || true
  kc get pods -n "$NAMESPACE" -o wide || true

  pods="$(selected_pods)"
  if [ -z "$pods" ]; then
    log "No pods selected."
    return
  fi

  for p in $pods; do
    case "$kind" in
      basic) check_one_basic "$p" ;;
      home) check_one_home "$p" ;;
      ssh) check_one_ssh "$p" ;;
      nodeport) check_one_nodeport "$p" ;;
      *) echo "Unknown check kind: $kind (expected: basic|home|ssh)" >&2; exit 2 ;;
    esac
  done
}

cmd_diagnose() {
  local full=0
  local crashloops=0

  parse_diagnose_arg() {
    case "$1" in
      --full) full=1; PARSE_ARG_CONSUMED=1; return 0 ;;
      --crashloops) crashloops=1; PARSE_ARG_CONSUMED=1; return 0 ;;
      *) return 1 ;;
    esac
  }

  parse_script_args usage parse_diagnose_arg "$@" || exit $?

  # Diagnose = alle Checks hintereinander.
  cmd_check basic
  cmd_check home
  cmd_check ssh
  cmd_check nodeport

  if [ "$full" -eq 1 ] && [ "$ALL" -eq 1 ]; then
    run_cmd "$SCRIPT_DIR/pd/collect_diagnostics.sh" -n "$NAMESPACE" -k "$KC_CMD"
    if [ "$crashloops" -eq 1 ]; then
      run_cmd "$SCRIPT_DIR/pd/diagnose_crashloops.sh" -n "$NAMESPACE" -k "$KC_CMD"
    fi
    return
  fi

  if [ "$full" -eq 1 ]; then
    local pods out
    pods="$(selected_pods)"
    [ -z "$pods" ] && return
    for pod in $pods; do
      out="${REPO_ROOT}/prepare_docker/out.diagnostics/$(ts)/pod-${pod}"
      run_cmd mkdir -p "$out"
      kc describe pod "$pod" -n "$NAMESPACE" > "$out/describe.txt" 2>&1 || true
      kc logs "$pod" -n "$NAMESPACE" --all-containers=true --tail=500 > "$out/logs.txt" 2>&1 || true
      kc logs "$pod" -n "$NAMESPACE" --all-containers=true --previous --tail=500 > "$out/logs_previous.txt" 2>&1 || true
      log "Diagnostics written to $out"
    done
  fi
}

cmd_assemble() {
  local level=""
  local do_verify=1

  parse_assemble_arg() {
    case "$1" in
      --level) level="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
      --no-verify) do_verify=0; PARSE_ARG_CONSUMED=1; return 0 ;;
      *) return 1 ;;
    esac
  }

  parse_script_args usage parse_assemble_arg "$@" || exit $?

  if [ -z "$level" ]; then
    if [ "$ALL" -eq 1 ]; then
      level="full"
    else
      level="pod"
    fi
  fi

  log "== assemble (level=$level all=$ALL)"

  case "$level" in
    full)
      if [ "$ALL" -eq 0 ]; then
        echo "WARN: assemble --level full ohne -a ergibt praktisch pod-level. Nutze -a fuer Cluster-Aktionen." >&2
      else
        run_cmd "$SCRIPT_DIR/pd/deploy-ssh-keys.sh"
        run_cmd "$SCRIPT_DIR/pd/gen_configmap_from_script.sh" -n "$NAMESPACE" -k "$KC_CMD"
        run_cmd "$SCRIPT_DIR/pd/restart_wls_rollouts.sh" -n "$NAMESPACE" -k "$KC_CMD"
      fi
      install_pubkey_selected
      ;;
    rollout)
      if [ "$ALL" -eq 0 ]; then
        echo "WARN: assemble --level rollout ohne -a ergibt praktisch pod-level. Nutze -a fuer Rollouts." >&2
      else
        run_cmd "$SCRIPT_DIR/pd/gen_configmap_from_script.sh" -n "$NAMESPACE" -k "$KC_CMD"
        run_cmd "$SCRIPT_DIR/pd/restart_wls_rollouts.sh" -n "$NAMESPACE" -k "$KC_CMD"
      fi
      install_pubkey_selected
      ;;
    pod)
      install_pubkey_selected
      ;;
    *)
      echo "ERROR: invalid assemble --level '$level' (expected: pod|rollout|full)" >&2
      exit 2
      ;;
  esac

  if [ "$do_verify" -eq 1 ]; then
    cmd_diagnose
  fi
}

cmd_down() {
  local level="resources" purge_data=0 auto_yes=0

  parse_down_arg() {
    case "$1" in
      --level) level="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
      --purge-data) purge_data=1; PARSE_ARG_CONSUMED=1; return 0 ;;
      -y|--yes) auto_yes=1; PARSE_ARG_CONSUMED=1; return 0 ;;
      *) return 1 ;;
    esac
  }

  parse_script_args usage parse_down_arg "$@" || exit $?

  if [ "$ALL" -eq 0 ]; then
    local pod
    pod="$(resolve_one_pod)"
    [ -z "$pod" ] && return
    kc delete pod "$pod" -n "$NAMESPACE" --grace-period=0 --force || true
    return
  fi

  local args=("$SCRIPT_DIR/pd/teardown_namespace.sh" -n "$NAMESPACE" -k "$KC_CMD")
  case "$level" in
    scale-down) args+=(--scale-down) ;;
    soft) args+=(--soft) ;;
    resources) args+=(--resources) ;;
    namespace) args+=(--namespace) ;;
    all) args+=(--all) ;;
    *) echo "ERROR: invalid --level '$level'" >&2; exit 2 ;;
  esac
  [ "$purge_data" -eq 1 ] && args+=(--purge-data)
  [ "$auto_yes" -eq 1 ] && args+=(--yes)
  run_cmd "${args[@]}"
}

COMMAND=""
COMMAND_ARGS=()
help_pd() {
  usage
  if [ -n "${SCRIPT_ARGS[0]:-}" ]; then
    echo ""
    usage_pd_command "${SCRIPT_ARGS[0]}"
  fi
  exit 0
}

parse_pd_global_arg() {
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; PARSE_ARG_CONSUMED=2; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    -k|--kc-cmd) KC_CMD="$2"; PARSE_ARG_CONSUMED=2; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    -a|--all) ALL=1; PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    --pod) POD="$2"; PARSE_ARG_CONSUMED=2; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    --label) LABEL="$2"; PARSE_ARG_CONSUMED=2; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    -v|--verbose) VERBOSE=$((VERBOSE+1)); PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    -q|--quiet) QUIET=1; PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    --log-file) LOG_FILE="$2"; PARSE_ARG_CONSUMED=2; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    --dry-run) DRY_RUN=1; PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    *) return 1 ;;
  esac
}

extract_pd_global_options_anywhere() {
  local remaining=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n|--namespace|-k|--kc-cmd|--pod|--label|--log-file)
        if [ $# -lt 2 ]; then
          echo "Missing value for global option: $1" >&2
          exit 2
        fi
        parse_pd_global_arg "$1" "$2" || {
          echo "Unknown global option: $1" >&2
          exit 2
        }
        shift 2
        ;;
      -a|--all|-v|--verbose|-q|--quiet|--dry-run)
        parse_pd_global_arg "$1" "" || {
          echo "Unknown global option: $1" >&2
          exit 2
        }
        shift
        ;;
      *)
        remaining+=("$1")
        shift
        ;;
    esac
  done
  COMMAND_ARGS=("${remaining[@]}")
}

parse_script_args help_pd parse_pd_global_arg "$@" || exit $?

COMMAND="${SCRIPT_ARGS[0]:-}"
if [ -z "$COMMAND" ]; then
  usage
  exit 0
fi
COMMAND_ARGS=("${SCRIPT_ARGS[@]:1}")

# Also accept global options after the command and interleaved with command args.
extract_pd_global_options_anywhere "${COMMAND_ARGS[@]}"

read -r -a KC_ARR <<<"$KC_CMD"

case "$COMMAND" in
  check) cmd_check "${COMMAND_ARGS[@]}" ;;
  diagnose) cmd_diagnose "${COMMAND_ARGS[@]}" ;;
  assemble) cmd_assemble "${COMMAND_ARGS[@]}" ;;
  down) cmd_down "${COMMAND_ARGS[@]}" ;;
  up)
    cmd_assemble "${COMMAND_ARGS[@]}"
    cmd_diagnose
    ;;
  doctor)
    cmd_diagnose --full --crashloops
    ;;
  *)
    echo "ERROR: unknown command: $COMMAND" >&2
    usage
    exit 2
    ;;
esac



