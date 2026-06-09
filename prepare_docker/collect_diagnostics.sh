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

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/diag_common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a) ALL_NS=1; shift 1; ;;
    --reap) DO_REAP=1; shift 1; ;;
    -h|--help) echo "Usage: $0 [-n namespace] [-k kc_cmd] [-a] [--reap]"; exit 0; ;;
    *) echo "Unknown arg: $1" >&2; exit 2; ;;
  esac
done

# initialize out dir (diag_common sets DIAG_OUT_DIR and echoes it)
OUT_DIR=$(diag_init_outdir)

echo "Collecting diagnostics into $OUT_DIR"
echo "KC_CMD: $KC_CMD" > "$OUT_DIR/metadata.txt"
echo "all_namespaces: $ALL_NS" >> "$OUT_DIR/metadata.txt"

# cluster-level
echo "== cluster: version" > "$OUT_DIR/cluster_version.txt"
$KC_CMD version --client=true > "$OUT_DIR/cluster_kubectl_version.txt" 2>&1 || true
$KC_CMD cluster-info dump > "$OUT_DIR/cluster_dump.txt" 2>&1 || true

echo "== nodes" > "$OUT_DIR/nodes.txt"
$KC_CMD get nodes -o wide > "$OUT_DIR/nodes.txt" 2>&1 || true

echo "== all pods (summary)" > "$OUT_DIR/pods_all.txt"
$KC_CMD get pods --all-namespaces -o wide > "$OUT_DIR/pods_all.txt" 2>&1 || true

echo "== events (all namespaces)" > "$OUT_DIR/events_all.txt"
$KC_CMD get events --all-namespaces --sort-by='.lastTimestamp' > "$OUT_DIR/events_all.txt" 2>&1 || true

# list namespaces to inspect
if [ "$ALL_NS" -eq 1 ]; then
  NAMESPACES=$($KC_CMD get ns -o name 2>/dev/null | sed 's|namespace/||')
else
  NAMESPACES="$NAMESPACE"
fi

for ns in $NAMESPACES; do
  nsdir="$OUT_DIR/ns-${ns}"
  mkdir -p "$nsdir"
  echo "Collecting namespace: $ns -> $nsdir"

  $KC_CMD get ns "$ns" -o yaml > "$nsdir/namespace.yaml" 2>&1 || true
  $KC_CMD get pods -n "$ns" -o wide > "$nsdir/pods.txt" 2>&1 || true
  $KC_CMD get deploy -n "$ns" -o wide > "$nsdir/deployments.txt" 2>&1 || true
  $KC_CMD get rs -n "$ns" -o wide > "$nsdir/replicasets.txt" 2>&1 || true
  $KC_CMD get svc -n "$ns" -o wide > "$nsdir/services.txt" 2>&1 || true
  $KC_CMD get pvc -n "$ns" -o wide > "$nsdir/pvcs.txt" 2>&1 || true

  # save YAMLs
  $KC_CMD get pods -n "$ns" -o yaml > "$nsdir/pods.yaml" 2>&1 || true
  $KC_CMD get deploy -n "$ns" -o yaml > "$nsdir/deployments.yaml" 2>&1 || true
  $KC_CMD get pvc -n "$ns" -o yaml > "$nsdir/pvcs.yaml" 2>&1 || true

  # iterate pods: describe + logs (use diag_common helper)
  pods=$($KC_CMD get pods -n "$ns" -o name 2>/dev/null | sed 's|pod/||')
  for p in $pods; do
    pd="$nsdir/pod-${p}"
    diag_collect_pod "$ns" "$p" "$pd" 500
    # best-effort collect node kubelet journal too
    node=$($KC_CMD get pod "$p" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
    if [ -n "$node" ]; then
      diag_collect_node_journal "$node" "$pd"
    fi
  done

  # identify Terminating pods for convenience
  $KC_CMD get pods -n "$ns" | awk '/Terminating/ {print $1}' > "$nsdir/terminating_pods.txt" 2>/dev/null || true

  # optionally run reap on this namespace
  if [ "$DO_REAP" -eq 1 ]; then
    if [ -x "$(pwd)/prepare_docker/reap_terminating.sh" ]; then
      echo "Running reap_terminating.sh for $ns" > "$nsdir/reap_action.txt"
      ./prepare_docker/reap_terminating.sh -n "$ns" >> "$nsdir/reap_action.txt" 2>&1 || true
    else
      echo "reap_terminating.sh not found or not executable; skipping" > "$nsdir/reap_action.txt"
    fi
  fi
done

echo "Diagnostics collected under: $OUT_DIR"
echo "Tip: tar/zip the directory for sharing: tar czf out.diagnostics/${TS}.tgz $OUT_DIR"

exit 0
