#!/usr/bin/env bash
set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Common utilities for prepare_docker scripts
# - load central defaults and optional local overrides

if [ -f "$COMMON_DIR/config.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "$COMMON_DIR/config.defaults.sh"
fi

if [ -f "$COMMON_DIR/config.local.sh" ]; then
  # shellcheck disable=SC1091
  source "$COMMON_DIR/config.local.sh"
fi

NAMESPACE_DEFAULT=${NAMESPACE_DEFAULT:-weblogic}
KC_CMD_DEFAULT=${KC_CMD_DEFAULT:-kc}
MK_PRF_DEFAULT=${MK_PRF_DEFAULT:-wlcluster}
MK_NODES_DEFAULT=${MK_NODES_DEFAULT:-3}
PV_PATH_DEFAULT=${PV_PATH_DEFAULT:-/mnt/weblogic/pv-home}
WLS_IMAGE_TAG_DEFAULT=${WLS_IMAGE_TAG_DEFAULT:-wls-dev:1.3}
PUBKEY_DEFAULT=${PUBKEY_DEFAULT:-${HOME}/.ssh/id_ed25519_docker.pub}
PRIVKEY_DEFAULT=${PRIVKEY_DEFAULT:-${HOME}/.ssh/id_ed25519_docker}
AUTO_YES_DEFAULT=${AUTO_YES_DEFAULT:-0}

NAMESPACE=${NAMESPACE:-$NAMESPACE_DEFAULT}
KC_CMD=${KC_CMD:-$KC_CMD_DEFAULT}
MK_PRF=${MK_PRF:-$MK_PRF_DEFAULT}
MK_NODES=${MK_NODES:-$MK_NODES_DEFAULT}
PV_PATH=${PV_PATH:-$PV_PATH_DEFAULT}
PUBKEY=${PUBKEY:-$PUBKEY_DEFAULT}
PRIVKEY=${PRIVKEY:-$PRIVKEY_DEFAULT}
IMAGE_TAG=${IMAGE_TAG:-$WLS_IMAGE_TAG_DEFAULT}
AUTO_YES=${AUTO_YES:-$AUTO_YES_DEFAULT}

KC_CMD_ARR=()

# usage_common_options
# Print the shared CLI options used by most prepare_docker scripts.
usage_common_options() {
  cat <<EOF
Common options:
  -n, --namespace <ns>   Namespace (default from config)
  -k, --kc-cmd <cmd>     kubectl wrapper (default from config)
EOF
}

# usage_render_script <usage_line> <local_usage_fn>
# Print a standard usage block with shared options and script-specific extras.
usage_render_script() {
  local usage_line="$1"
  local local_usage_fn="${2:-}"

  cat <<EOF
Usage: $usage_line
EOF
  usage_common_options
  if [ -n "$local_usage_fn" ]; then
    echo "Extra options:"
    "$local_usage_fn"
  fi
}

# parse_common_args <args...>
# consumes -n <namespace> and -k <kc_cmd> options and prints the number
# of argv entries consumed. Caller should then `shift $consumed`.
parse_common_args() {
  local consumed=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n)
        if [ $# -lt 2 ]; then
          echo "parse_common_args: -n requires an argument" >&2
          return 1
        fi
        NAMESPACE="$2"
        consumed=$((consumed+2))
        shift 2
        ;;
      -k)
        if [ $# -lt 2 ]; then
          echo "parse_common_args: -k requires an argument" >&2
          return 1
        fi
        KC_CMD="$2"
        consumed=$((consumed+2))
        shift 2
        ;;
      --)
        consumed=$((consumed+1))
        shift 1
        break
        ;;
      -*)
        # unknown option: stop and leave it for caller
        break
        ;;
      *)
        break
        ;;
    esac
  done
  printf "%d" "$consumed"
}

# parse_script_args <help_fn> <local_parser_fn> <args...>
# Generic CLI parser for prepare_docker shell scripts.
#
# Behavior:
# - handles shared flags: -n/--namespace and -k/--kc-cmd
# - handles help: -h/--help via help_fn
# - delegates unknown flags to local_parser_fn
#
# The local parser must set PARSE_ARG_CONSUMED to the number of argv entries
# it consumed (typically 1 or 2) and return 0 if it handled the option.
# Parsed leftover args are written to SCRIPT_ARGS as an array.
parse_script_args() {
  local help_fn="$1"
  local local_parser_fn="$2"
  shift 2

  SCRIPT_ARGS=()
  PARSE_ARG_CONSUMED=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n)
        if [ $# -lt 2 ]; then
          echo "parse_script_args: -n requires an argument" >&2
          return 1
        fi
        NAMESPACE="$2"
        shift 2
        ;;
      -k)
        if [ $# -lt 2 ]; then
          echo "parse_script_args: -k requires an argument" >&2
          return 1
        fi
        KC_CMD="$2"
        shift 2
        ;;
      -h|--help)
        "$help_fn"
        return 0
        ;;
      --)
        shift
        SCRIPT_ARGS=("$@")
        return 0
        ;;
      -*)
        PARSE_ARG_CONSUMED=0
        if "$local_parser_fn" "$1" "${2-}"; then
          if [ "$PARSE_ARG_CONSUMED" -lt 1 ]; then
            PARSE_ARG_CONSUMED=1
          fi
          shift "$PARSE_ARG_CONSUMED"
        else
          echo "Unknown arg: $1" >&2
          return 2
        fi
        ;;
      *)
        SCRIPT_ARGS=("$@")
        return 0
        ;;
    esac
  done

  return 0
}

# init_kc_cmd
# Parse KC_CMD once into an argv array so wrappers like
# "minikube -p wlcluster kubectl --" are handled safely.
init_kc_cmd() {
  read -r -a KC_CMD_ARR <<<"${KC_CMD:-kc}"
}

# resolve_kc_exec
# Return a real executable path for the default `kc` command so the shell
# function does not recurse into itself when KC_CMD is left at the default.
resolve_kc_exec() {
  local kc_exec
  kc_exec="$(type -P kc 2>/dev/null || true)"
  if [ -z "$kc_exec" ] && [ -x "$COMMON_DIR/../tools/kc" ]; then
    kc_exec="$COMMON_DIR/../tools/kc"
  fi
  printf '%s' "$kc_exec"
}

# kc <kubectl args...>
# Run the configured kubectl wrapper command.
kc() {
  if [ "${#KC_CMD_ARR[@]}" -eq 0 ]; then
    init_kc_cmd
  fi
  if [ "${KC_CMD_ARR[0]}" = "kc" ]; then
    local kc_exec
    kc_exec="$(resolve_kc_exec)"
    if [ -z "$kc_exec" ]; then
      echo "ERROR: kc wrapper not found in PATH and $COMMON_DIR/../tools/kc is not executable" >&2
      return 127
    fi
    "$kc_exec" "$@"
  else
    "${KC_CMD_ARR[@]}" "$@"
  fi
}

# require_file <path> <label>
# Fail with a clear error when required files are missing.
require_file() {
  local path="$1"
  local label="${2:-file}"
  if [ ! -f "$path" ]; then
    echo "${label} not found: $path" >&2
    return 2
  fi
}

# backup_if_exists <file>
# If the file exists, move it to a timestamped backup (before extension).
backup_if_exists() {
  local target="$1"
  if [ -f "$target" ]; then
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local dir
    dir=$(dirname -- "$target")
    local filename
    filename=$(basename -- "$target")
    if [[ "$filename" == *.* ]]; then
      local base ext
      base="${filename%.*}"
      ext="${filename##*.}"
      mv -- "$target" "$dir/${base}.${ts}.${ext}"
    else
      mv -- "$target" "$dir/${filename}.${ts}"
    fi
  fi
}

