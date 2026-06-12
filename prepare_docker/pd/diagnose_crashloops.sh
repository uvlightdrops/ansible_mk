#!/usr/bin/env bash
set -euo pipefail

# diagnose_crashloops.sh
# Collect focused diagnostics for pods in CrashLoopBackOff state.
# Usage: ./diagnose_crashloops.sh [-n namespace] [-k kc_cmd] [-a] [-t tail_lines] [-o outdir]
#  -n namespace (default: weblogic)
#  -k kc_cmd    (default: kc)
#  -a collect for all namespaces
#  -t tail_lines (default: 500)
#  -o outdir (default: out.diagnostics/<ts>/crashloops)

ALL_NS=0
TAIL=500
OUT_BASE=

source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../diag_common.sh"

help_diagnose_crashloops() {
  diagnose_crashloops_usage_extra() {
    cat <<EOF
  -a collect for all namespaces
  -t tail_lines (default: 500)
  -o outdir (default: out.diagnostics/<ts>/crashloops)
EOF
  }
  usage_render_script "$0 [-a] [-t tail_lines] [-o outdir]" diagnose_crashloops_usage_extra
  exit 0
}

parse_diagnose_crashloops_arg() {
  case "$1" in
    -a) ALL_NS=1; PARSE_ARG_CONSUMED=1; return 0 ;;
    -t) TAIL="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    -o) OUT_BASE="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_diagnose_crashloops parse_diagnose_crashloops_arg "$@" || exit $?

OUT_BASE=${OUT_BASE:-$(diag_init_outdir)/crashloops}
mkdir -p "$OUT_BASE"

echo "Writing crashloop diagnostics to: $OUT_BASE"

pods_list()
{
  if [ "$ALL_NS" -eq 1 ]; then
    # global: namespace|pod|reasons
    kc get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.state.waiting.reason}{";"}{end}{"\n"}{end}' 2>/dev/null |
      awk -F"|" '/CrashLoopBackOff/ {print $1" " $2}'
  else
    kc get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.state.waiting.reason}{";"}{end}{"\n"}{end}' 2>/dev/null |
      awk -F"|" '/CrashLoopBackOff/ {print $1" " $2}'
  fi
}

pods=$(pods_list)
if [ -z "$pods" ]; then
  echo "No CrashLoopBackOff pods found (namespace=${NAMESPACE}, all=${ALL_NS})"
  exit 0
fi

echo "$pods" | while read -r ns pod; do
  echo "Collecting: $ns/$pod"
  pd="$OUT_BASE/${ns}_${pod}"
  mkdir -p "$pd"
  diag_collect_pod "$ns" "$pod" "$pd" "$TAIL"
  # best-effort node kubelet journal
  node=$(kc get pod "$pod" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  if [ -n "$node" ]; then
    diag_collect_node_journal "$node" "$pd"
  fi

done

echo "Done. Files written under $OUT_BASE"

exit 0

