#!/usr/bin/env bash
set -euo pipefail

# Common utilities for prepare_docker scripts
# - default variables
NAMESPACE=${NAMESPACE:-weblogic}
KC_CMD=${KC_CMD:-kc}

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

