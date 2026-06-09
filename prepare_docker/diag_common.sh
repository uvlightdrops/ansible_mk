#!/usr/bin/env bash
set -euo pipefail

# Helper functions for diagnostics scripts
# Source this file from diagnostics scripts to reuse common logic.

KC_CMD="${KC_CMD:-kc}"

# diag_init_outdir [out_dir] - initialize timestamped out dir or use given
# sets DIAG_OUT_DIR global
diag_init_outdir() {
  local provided=${1:-}
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  if [ -n "$provided" ]; then
    DIAG_OUT_DIR="$provided"
  else
    DIAG_OUT_DIR="out.diagnostics/${ts}"
  fi
  mkdir -p "$DIAG_OUT_DIR"
  echo "$DIAG_OUT_DIR"
}

# diag_collect_pod <namespace> <pod> <destdir> [tail]
# collects describe, pod yaml, container logs (current + previous), and events
diag_collect_pod() {
  local ns=$1
  local pod=$2
  local dest=$3
  local tail=${4:-500}
  mkdir -p "$dest"
  echo "Collecting pod $ns/$pod -> $dest"
  $KC_CMD describe pod "$pod" -n "$ns" > "$dest/describe.txt" 2>&1 || true
  $KC_CMD get pod "$pod" -n "$ns" -o yaml > "$dest/pod.yaml" 2>&1 || true

  # node
  local node
  node=$($KC_CMD get pod "$pod" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  echo "node: $node" > "$dest/node.txt"

  # containers
  local containers
  local init_containers
  containers=$($KC_CMD get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)
  init_containers=$($KC_CMD get pod "$pod" -n "$ns" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || true)

  for c in $containers; do
    $KC_CMD logs -n "$ns" "$pod" -c "$c" --tail=$tail > "$dest/log.${c}.txt" 2>&1 || true
    $KC_CMD logs -n "$ns" "$pod" -c "$c" --previous --tail=$tail > "$dest/log.${c}.previous.txt" 2>&1 || true
  done
  for c in $init_containers; do
    $KC_CMD logs -n "$ns" "$pod" -c "$c" --tail=$tail > "$dest/log.init.${c}.txt" 2>&1 || true
  done

  $KC_CMD get events -n "$ns" --field-selector involvedObject.name="$pod" --sort-by='.lastTimestamp' > "$dest/events.txt" 2>&1 || true
}

# diag_collect_node_journal <node> <destdir>
# best-effort: if minikube node exists as docker container, fetch kubelet journal
diag_collect_node_journal() {
  local node=$1
  local dest=$2
  mkdir -p "$dest"
  if [ -z "$node" ]; then
    echo "no node provided"
    return 0
  fi
  $KC_CMD describe node "$node" > "$dest/node.describe.txt" 2>&1 || true
  # try docker container with same name
  if command -v docker >/dev/null 2>&1; then
    local docker_name
    docker_name=$(docker ps --format '{{.Names}}' | grep -F "${node}" || true)
    if [ -n "$docker_name" ]; then
      docker exec -u root "$docker_name" sh -c 'journalctl -u kubelet --no-pager -n 200' > "$dest/node.kubelet.journal.txt" 2>&1 || true
    fi
  fi
}


