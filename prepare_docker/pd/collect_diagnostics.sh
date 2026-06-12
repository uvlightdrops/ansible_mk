#!/usr/bin/env bash
set -euo pipefail

# collect_diagnostics.sh
# Collect cluster and namespace diagnostics into a timestamped directory under out.diagnostics/
# Usage: ./collect_diagnostics.sh [-n namespace] [-k kc_cmd] [-a] [--reap]
#  -n namespace  (default: weblogic)
#  -k kc_cmd     (default: kc)
#  -a            collect for all namespaces
#  --reap        after collecting diagnostics, run reap_terminating.sh -n <ns> for each ns

ALL_NS=0
DO_REAP=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BASE_DIR/common.sh"
source "$BASE_DIR/diag_common.sh"

help_collect_diagnostics() {
  collect_diagnostics_usage_extra() {
    cat <<EOF
  -a            collect for all namespaces
  --reap        after collecting diagnostics, run reap_terminating.sh for each namespace
EOF
  }
  usage_render_script "$0 [-a] [--reap]" collect_diagnostics_usage_extra
  exit 0
}

parse_collect_diagnostics_arg() {
  case "$1" in
    -a) ALL_NS=1; PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    --reap) DO_REAP=1; PARSE_ARG_CONSUMED=1; : "${PARSE_ARG_CONSUMED}"; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_collect_diagnostics parse_collect_diagnostics_arg "$@" || exit $?

# initialize out dir (diag_common sets DIAG_OUT_DIR and echoes it)
OUT_DIR=$(diag_init_outdir)

echo "KC_CMD: $KC_CMD" > "$OUT_DIR/metadata.txt"
echo "all_namespaces: $ALL_NS" >> "$OUT_DIR/metadata.txt"

# cluster-level
echo "== cluster: version" > "$OUT_DIR/cluster_version.txt"
kc version --client=true > "$OUT_DIR/cluster_kubectl_version.txt" 2>&1 || true
kc cluster-info dump > "$OUT_DIR/cluster_dump.txt" 2>&1 || true

echo "== nodes" > "$OUT_DIR/nodes.txt"
kc get nodes -o wide > "$OUT_DIR/nodes.txt" 2>&1 || true

echo "== all pods (summary)" > "$OUT_DIR/pods_all.txt"
kc get pods --all-namespaces -o wide > "$OUT_DIR/pods_all.txt" 2>&1 || true

echo "== events (all namespaces)" > "$OUT_DIR/events_all.txt"
kc get events --all-namespaces --sort-by='.lastTimestamp' > "$OUT_DIR/events_all.txt" 2>&1 || true

# list namespaces to inspect
if [ "$ALL_NS" -eq 1 ]; then
  NAMESPACES=$(kc get ns -o name 2>/dev/null | sed 's|namespace/||')
else
  NAMESPACES="$NAMESPACE"
fi

for ns in $NAMESPACES; do
  nsdir="$OUT_DIR/ns-${ns}"
  mkdir -p "$nsdir"
  echo "Collecting namespace: $ns -> $nsdir"

  kc get ns "$ns" -o yaml > "$nsdir/namespace.yaml" 2>&1 || true
  kc get pods -n "$ns" -o wide > "$nsdir/pods.txt" 2>&1 || true
  kc get deploy -n "$ns" -o wide > "$nsdir/deployments.txt" 2>&1 || true
  kc get statefulset -n "$ns" -o wide > "$nsdir/statefulsets.txt" 2>&1 || true
  kc get rs -n "$ns" -o wide > "$nsdir/replicasets.txt" 2>&1 || true
  kc get svc -n "$ns" -o wide > "$nsdir/services.txt" 2>&1 || true
  kc get pvc -n "$ns" -o wide > "$nsdir/pvcs.txt" 2>&1 || true

  # save YAMLs
  kc get pods -n "$ns" -o yaml > "$nsdir/pods.yaml" 2>&1 || true
  kc get deploy -n "$ns" -o yaml > "$nsdir/deployments.yaml" 2>&1 || true
  kc get statefulset -n "$ns" -o yaml > "$nsdir/statefulsets.yaml" 2>&1 || true
  kc get pvc -n "$ns" -o yaml > "$nsdir/pvcs.yaml" 2>&1 || true

  # iterate pods: describe + logs (use diag_common helper)
  pods=$(kc get pods -n "$ns" -o name 2>/dev/null | sed 's|pod/||')
  for p in $pods; do
    pd="$nsdir/pod-${p}"
    diag_collect_pod "$ns" "$p" "$pd" 500
    # best-effort collect node kubelet journal too
    node=$(kc get pod "$p" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
    if [ -n "$node" ]; then
      diag_collect_node_journal "$node" "$pd"
    fi
  done

  # identify Terminating pods for convenience
  kc get pods -n "$ns" | awk '/Terminating/ {print $1}' > "$nsdir/terminating_pods.txt" 2>/dev/null || true

  # optionally run reap on this namespace
  if [ "$DO_REAP" -eq 1 ]; then
    if [ -x "$BASE_DIR/reap_terminating.sh" ]; then
      echo "Running reap_terminating.sh for $ns" > "$nsdir/reap_action.txt"
      "$BASE_DIR/reap_terminating.sh" -n "$ns" >> "$nsdir/reap_action.txt" 2>&1 || true
    else
      echo "reap_terminating.sh not found or not executable; skipping" > "$nsdir/reap_action.txt"
    fi
  fi
done

printf '%s\n' "$OUT_DIR"

exit 0

