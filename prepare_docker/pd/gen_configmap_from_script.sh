#!/usr/bin/env bash
set -euo pipefail

# Generate the gen-ssh-keys ConfigMap YAML from the local script and apply it
# See -h/--help for usage.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SCRIPT_PATH="$REPO_ROOT/prepare_docker/gen-ssh-keys.sh"
OUT_YAML="$REPO_ROOT/k8s/gen-ssh-keys-config.yaml"

source "$SCRIPT_DIR/../common.sh"

help_gen_configmap_from_script() {
  gen_configmap_usage_extra() {
    cat <<EOF
  -s script      script file for ConfigMap (default: <repo>/prepare_docker/gen-ssh-keys.sh)
  -o out_yaml    output yaml path (default: <repo>/k8s/gen-ssh-keys-config.yaml)
EOF
  }
  usage_render_script "$0 [-s script_path] [-o out_yaml]" gen_configmap_usage_extra
  exit 0
}

parse_gen_configmap_from_script_arg() {
  case "$1" in
  -s|--script) SCRIPT_PATH="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
  -o|--out) OUT_YAML="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
  *) return 1 ;;
  esac
}

parse_script_args help_gen_configmap_from_script parse_gen_configmap_from_script_arg "$@" || exit $?

init_kc_cmd

require_file "$SCRIPT_PATH" "Script" || exit $?

# After full teardown the namespace may not exist yet.
if ! kc get namespace "$NAMESPACE" >/dev/null 2>&1; then
  kc create namespace "$NAMESPACE" >/dev/null
fi

kc create configmap gen-ssh-keys-script --from-file="$SCRIPT_PATH" -n "$NAMESPACE" --dry-run=client -o yaml > "$OUT_YAML"
kc apply -f "$OUT_YAML" >/dev/null

printf '%s\n' "$OUT_YAML"


