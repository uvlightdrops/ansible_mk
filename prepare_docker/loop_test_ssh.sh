#!/usr/bin/env bash
set -euo pipefail

# Test SSH connectivity to WLS pods via NodePort services
# Usage: ./loop_test_ssh.sh [-n namespace] [-k kc_cmd] [-i identity_file] [-u user] [-t timeout]

NAMESPACE="weblogic"
KC_CMD="${KC_CMD:-kc}"
IDENTITY_FILE="${HOME}/.ssh/id_ed25519_docker"
SSH_USER="docker"
CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-5}

# source common helpers and parse common args (-n -k)
source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

OPTIND=1
while getopts ":i:u:t:?" opt; do
  case "$opt" in
    i) IDENTITY_FILE="$OPTARG" ;;
    u) SSH_USER="$OPTARG" ;;
    t) CONNECT_TIMEOUT="$OPTARG" ;;
    *) echo "Usage: $0 [-n namespace] [-k kc_cmd] [-i identity_file] [-u ssh_user] [-t timeout]"; exit 1 ;;
  esac
done


if [ ! -f "$IDENTITY_FILE" ]; then
  echo "Warning: identity file not found: $IDENTITY_FILE" >&2
fi

# Determine a Node IP to reach NodePorts
NODE_IP=""
NODE_IP=$($KC_CMD get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
if [ -z "$NODE_IP" ]; then
  # fallback to minikube ip
  if command -v minikube >/dev/null 2>&1; then
    NODE_IP=$(minikube ip 2>/dev/null || true)
  fi
fi
if [ -z "$NODE_IP" ]; then
  echo "Could not determine node IP. Supply KC_CMD that points to your cluster or ensure minikube is available." >&2
  exit 3
fi

SERVICES=(wls-admin-ssh-nodeport wls-managed-1-ssh-nodeport wls-managed-2-ssh-nodeport wls-managed-3-ssh-nodeport)

echo "Testing SSH to Node $NODE_IP (namespace: $NAMESPACE) with user $SSH_USER"

for svc in "${SERVICES[@]}"; do
  echo
  echo "================================================================="
  echo " Service: $svc"
  echo "================================================================="
  # get nodePort for port 22
  nodePort=$($KC_CMD get svc -n "$NAMESPACE" "$svc" -o jsonpath='{.spec.ports[?(@.port==22)].nodePort}' 2>/dev/null || true)
  if [ -z "$nodePort" ]; then
    echo "Service $svc not found or no port 22 -> skipping"
    continue
  fi

  echo -n "$svc -> $NODE_IP:$nodePort ... "
  ssh_opts=( -o BatchMode=yes -o ConnectTimeout=$CONNECT_TIMEOUT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )
  id_arg=""
  if [ -f "$IDENTITY_FILE" ]; then
    id_arg="-i $IDENTITY_FILE"
  fi
  # human-readable command string
  SSH_CMD_STR="ssh $id_arg -p $nodePort ${ssh_opts[*]} $SSH_USER@$NODE_IP 'echo SSH_OK'"
  echo "SSH command: $SSH_CMD_STR"

  if ssh ${id_arg} "${ssh_opts[@]}" -p "$nodePort" "$SSH_USER"@"$NODE_IP" 'echo SSH_OK' >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAILED"
    echo "Gathering debug info for service $svc..."
    # prepare output directory
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    OUT_BASE="$REPO_ROOT/out/ssh_check"
    svc_dir="$OUT_BASE/$svc"
    mkdir -p "$svc_dir"

    echo "Saving full Service YAML to $svc_dir/service.yaml"
    backup_if_exists "$svc_dir/service.yaml"
    $KC_CMD get svc -n "$NAMESPACE" "$svc" -o yaml > "$svc_dir/service.yaml" 2>&1 || true
    echo "Saving Endpoints to $svc_dir/endpoints.yaml"
    backup_if_exists "$svc_dir/endpoints.yaml"
    $KC_CMD get endpoints -n "$NAMESPACE" "$svc" -o yaml > "$svc_dir/endpoints.yaml" 2>&1 || true

    # try to find backing pod names from endpoints
    podnames=$($KC_CMD get endpoints -n "$NAMESPACE" "$svc" -o jsonpath='{range .subsets[*].addresses[*]}{.targetRef.name} {end}' 2>/dev/null || true)
    if [ -n "$podnames" ]; then
      for p in $podnames; do
        echo
        echo "-----------------------------------------------------------------"
        echo " Pod: $p"
        echo "-----------------------------------------------------------------"
        echo "Saving full describe for pod $p -> $svc_dir/${p}.describe.txt"
        backup_if_exists "$svc_dir/${p}.describe.txt"
        $KC_CMD describe pod -n "$NAMESPACE" "$p" > "$svc_dir/${p}.describe.txt" 2>&1 || true
        echo "Saving full pod YAML for $p -> $svc_dir/${p}.yaml"
        backup_if_exists "$svc_dir/${p}.yaml"
        $KC_CMD get pod -n "$NAMESPACE" "$p" -o yaml > "$svc_dir/${p}.yaml" 2>&1 || true

        # print compact summary to console: first 10 lines and last 10 events
        echo "--- Pod summary: $p ---"
        $KC_CMD describe pod -n "$NAMESPACE" "$p" | sed -n '1,10p' || true
        echo "--- Recent events (last 10 lines) ---"
        $KC_CMD describe pod -n "$NAMESPACE" "$p" | sed -n '/Events:/,$p' | tail -n 10 || true
      done
    else
      echo "No endpoints found; saving pod list to $svc_dir/pods.txt"
      backup_if_exists "$svc_dir/pods.txt"
      $KC_CMD get pods -n "$NAMESPACE" -o wide > "$svc_dir/pods.txt" 2>&1 || true
      echo "No endpoints found; showing brief pod list:"
      $KC_CMD get pods -n "$NAMESPACE" -o wide || true
    fi

    echo "Full diagnostics saved under: $svc_dir"
  fi
done

echo "Done."

