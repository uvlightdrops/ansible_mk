#!/usr/bin/env bash
# Collect diagnostics for a multi-node Minikube setup (container-based)
# Creates readable output that helps debugging "NotReady" nodes

set -euo pipefail

CONTAINER_PREFIX=${CONTAINER_PREFIX:-wlcluster}
KUBECTL=${KUBECTL:-"minikube -p ${MK_PRF:-wlcluster} kubectl --"}

echo "Using container prefix: $CONTAINER_PREFIX"
echo

echo "==> kubectl get nodes"
eval $KUBECTL get nodes || true
echo

echo "==> kubectl get pods -n kube-system -o wide"
eval $KUBECTL get pods -n kube-system -o wide || true
echo

containers=$(docker ps --format '{{.Names}}' | grep "^${CONTAINER_PREFIX}" || true)
if [ -z "$containers" ]; then
  echo "Keine Container mit Prefix '$CONTAINER_PREFIX' gefunden. Liste aller Container:"
  docker ps --format '{{.Names}}'
  exit 1
fi

for c in $containers; do
  echo "================================================================"
  echo "Container: $c"
  echo "----------------------------------------------------------------"
  echo "Hostname inside container:"
  docker exec -u root "$c" hostname || true
  echo

  echo "/etc/os-release:"
  docker exec -u root "$c" cat /etc/os-release 2>/dev/null || true
  echo

  echo "systemctl status kubelet (if available):"
  docker exec -u root "$c" systemctl status kubelet --no-pager 2>/dev/null || true
  echo

  echo "Last 200 lines of kubelet journal (if journalctl available):"
  docker exec -u root "$c" journalctl -u kubelet --no-pager -n 200 2>/dev/null || true
  echo

  echo "kubelet process (ps aux | grep kubelet):"
  docker exec -u root "$c" ps aux | grep kubelet || true
  echo

  echo "/var/log/syslog (last 200 lines) if present:"
  docker exec -u root "$c" tail -n 200 /var/log/syslog 2>/dev/null || true
  echo

  echo "/var/lib/kubelet/config.yaml (head):"
  docker exec -u root "$c" sh -c 'if [ -f /var/lib/kubelet/config.yaml ]; then echo "-- file exists --"; head -n 60 /var/lib/kubelet/config.yaml; else echo "no config.yaml"; fi' 2>/dev/null || true
  echo

  echo "kubeadm join logs (journal if available):"
  docker exec -u root "$c" journalctl -u kubeadm --no-pager -n 200 2>/dev/null || true
  echo

  echo "Docker/Container runtime status (ps/containers):"
  docker exec -u root "$c" ps -ef | grep -E 'containerd|dockerd|docker' || true
  echo

  echo "Events from kube-apiserver about this node (via kubectl):"
  NODE_NAME=$(docker exec -u root "$c" hostname 2>/dev/null || true)
  if [ -n "$NODE_NAME" ]; then
    echo "kubectl describe node $NODE_NAME -> Events:"
    eval $KUBECTL describe node "$NODE_NAME" || true
  fi
  echo
done

echo "Done. Review output for 'Kubelet', 'Network', 'CNI' or certificate/join errors."

