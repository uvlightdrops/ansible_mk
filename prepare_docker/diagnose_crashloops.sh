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

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/diag_common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a) ALL_NS=1; shift 1; ;;
    -t) TAIL="$2"; shift 2; ;;
    -o) OUT_BASE="$2"; shift 2; ;;
    -h|--help) echo "Usage: $0 [-n namespace] [-k kc_cmd] [-a] [-t tail_lines] [-o outdir]"; exit 0; ;;
    *) echo "Unknown arg: $1" >&2; exit 2; ;;
  esac
done

OUT_BASE=${OUT_BASE:-$(diag_init_outdir)/crashloops}
mkdir -p "$OUT_BASE"

echo "Writing crashloop diagnostics to: $OUT_BASE"

pods_list()
{
  if [ "$ALL_NS" -eq 1 ]; then
    # global: namespace|pod|reasons
    $KC_CMD get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.state.waiting.reason}{";"}{end}{"\n"}{end}' 2>/dev/null |
      awk -F"|" '/CrashLoopBackOff/ {print $1" " $2}'
  else
    $KC_CMD get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.state.waiting.reason}{";"}{end}{"\n"}{end}' 2>/dev/null |
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
  node=$($KC_CMD get pod "$pod" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  if [ -n "$node" ]; then
    diag_collect_node_journal "$node" "$pd"
  fi

done

echo "Done. Files written under $OUT_BASE"

exit 0
