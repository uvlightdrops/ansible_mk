#!/usr/bin/env bash
set -euo pipefail

# Generate inventory.yaml from a real Kubernetes cluster (current kubectl context).
# Usage examples:
#   ANSIBLE_SSH_KEY=~/.ssh/id_ed25519 ./scripts/generate_inventory_k8s.sh
#   KC_CMD="kubectl --context prod" ./scripts/generate_inventory_k8s.sh -n wl

NAMESPACE="wl"
OUT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/inventory.yaml"
KC_CMD="${KC_CMD:-kubectl}"
KEY_PATH="${ANSIBLE_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_USER="${ANSIBLE_SSH_USER:-docker}"
NODEPORT_HOST="${ANSIBLE_NODEPORT_HOST:-}"

usage() {
  cat <<'EOF'
Usage: scripts/generate_inventory_k8s.sh [options]

Options:
  -n, --namespace <ns>       Namespace for NodePort services (default: wl)
  -o, --out-file <path>      Output file (default: <repo>/inventory.yaml)
      --kc-cmd <cmd>         kubectl command (default: $KC_CMD or kubectl)
      --ssh-key <path>       SSH private key path (default: ~/.ssh/id_ed25519)
      --ssh-user <user>      SSH user (default: docker)
      --nodeport-host <ip>   Override ansible_host for weblogic_ssh entries
  -h, --help                 Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -o|--out-file)
      OUT_FILE="$2"
      shift 2
      ;;
    --kc-cmd)
      KC_CMD="$2"
      shift 2
      ;;
    --ssh-key)
      KEY_PATH="$2"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="$2"
      shift 2
      ;;
    --nodeport-host)
      NODEPORT_HOST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Split KC_CMD into an argv array (works for normal commands like 'kubectl --context X').
read -r -a KC <<<"$KC_CMD"

run_kc() {
  "${KC[@]}" "$@"
}

pick_ip_from_addresses() {
  # Input format: "InternalIP=10.0.0.5,Hostname=node1,..."
  local addresses="$1"
  local item type value

  IFS=',' read -r -a parts <<<"$addresses"

  for item in "${parts[@]}"; do
    type="${item%%=*}"
    value="${item#*=}"
    if [ "$type" = "InternalIP" ] && [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done

  for item in "${parts[@]}"; do
    type="${item%%=*}"
    value="${item#*=}"
    if [ "$type" = "ExternalIP" ] && [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done

  for item in "${parts[@]}"; do
    type="${item%%=*}"
    value="${item#*=}"
    if [ "$type" = "Hostname" ] && [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done

  return 1
}

get_nodeport() {
  local svc_name="$1"
  run_kc -n "$NAMESPACE" get svc "$svc_name" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true
}

echo "Reading Kubernetes nodes via: $KC_CMD"
NODE_LINES="$(run_kc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"|"}{.metadata.labels.node-role\.kubernetes\.io/master}{"|"}{range .status.addresses[*]}{.type}{"="}{.address}{","}{end}{"\n"}{end}')"

if [ -z "$NODE_LINES" ]; then
  echo "No nodes returned by kubectl." >&2
  exit 1
fi

CONTROL_TMP="$(mktemp)"
WORKER_TMP="$(mktemp)"
trap 'rm -f "$CONTROL_TMP" "$WORKER_TMP"' EXIT

FIRST_CONTROL_IP=""
FIRST_WORKER_IP=""

while IFS='|' read -r name cp_label master_label addresses; do
  [ -z "$name" ] && continue

  if ! ip="$(pick_ip_from_addresses "$addresses")"; then
    continue
  fi

  if [ -n "$cp_label" ] || [ -n "$master_label" ]; then
    printf '%s|%s\n' "$name" "$ip" >> "$CONTROL_TMP"
    [ -z "$FIRST_CONTROL_IP" ] && FIRST_CONTROL_IP="$ip"
  else
    printf '%s|%s\n' "$name" "$ip" >> "$WORKER_TMP"
    [ -z "$FIRST_WORKER_IP" ] && FIRST_WORKER_IP="$ip"
  fi
done <<< "$NODE_LINES"

if [ ! -s "$CONTROL_TMP" ] && [ ! -s "$WORKER_TMP" ]; then
  echo "No usable nodes found (missing node IPs)." >&2
  exit 1
fi

if [ -z "$NODEPORT_HOST" ]; then
  if [ -n "$FIRST_CONTROL_IP" ]; then
    NODEPORT_HOST="$FIRST_CONTROL_IP"
  else
    NODEPORT_HOST="$FIRST_WORKER_IP"
  fi
fi

if [ -z "$NODEPORT_HOST" ]; then
  echo "Could not determine nodeport host IP; use --nodeport-host." >&2
  exit 1
fi

ADMIN_PORT="$(get_nodeport wls-admin-ssh-nodeport)"
M1_PORT="$(get_nodeport wls-managed-1-ssh-nodeport)"
M2_PORT="$(get_nodeport wls-managed-2-ssh-nodeport)"

mkdir -p "$(dirname "$OUT_FILE")"

{
  echo "all:"
  echo "  children:"
  echo "    control:"
  echo "      hosts:"
  if [ -s "$CONTROL_TMP" ]; then
    while IFS='|' read -r name ip; do
      echo "        ${name}:"
      echo "          ansible_host: ${ip}"
      echo "          ansible_user: ${SSH_USER}"
      echo "          ansible_ssh_private_key_file: ${KEY_PATH}"
    done < "$CONTROL_TMP"
  else
    echo "        # no hosts detected"
  fi

  echo "    workers:"
  echo "      hosts:"
  if [ -s "$WORKER_TMP" ]; then
    while IFS='|' read -r name ip; do
      echo "        ${name}:"
      echo "          ansible_host: ${ip}"
      echo "          ansible_user: ${SSH_USER}"
      echo "          ansible_ssh_private_key_file: ${KEY_PATH}"
    done < "$WORKER_TMP"
  else
    echo "        # no hosts detected"
  fi

  echo "    weblogic_ssh:"
  echo "      hosts:"
  wrote_np=0
  if [ -n "$ADMIN_PORT" ]; then
    echo "        wls-admin-node:"
    echo "          ansible_host: ${NODEPORT_HOST}"
    echo "          ansible_port: ${ADMIN_PORT}"
    echo "          ansible_user: ${SSH_USER}"
    echo "          ansible_ssh_private_key_file: ${KEY_PATH}"
    wrote_np=1
  fi
  if [ -n "$M1_PORT" ]; then
    echo "        wls-managed-1-node:"
    echo "          ansible_host: ${NODEPORT_HOST}"
    echo "          ansible_port: ${M1_PORT}"
    echo "          ansible_user: ${SSH_USER}"
    echo "          ansible_ssh_private_key_file: ${KEY_PATH}"
    wrote_np=1
  fi
  if [ -n "$M2_PORT" ]; then
    echo "        wls-managed-2-node:"
    echo "          ansible_host: ${NODEPORT_HOST}"
    echo "          ansible_port: ${M2_PORT}"
    echo "          ansible_user: ${SSH_USER}"
    echo "          ansible_ssh_private_key_file: ${KEY_PATH}"
    wrote_np=1
  fi
  if [ "$wrote_np" -eq 0 ]; then
    echo "        # no matching NodePort services found in namespace"
  fi

  echo
  echo "# You can add group_vars under group_vars/ directory or edit this file to add vars."
} > "$OUT_FILE"

control_count=$(wc -l < "$CONTROL_TMP" | tr -d ' ')
worker_count=$(wc -l < "$WORKER_TMP" | tr -d ' ')
nodeport_count=0
[ -n "$ADMIN_PORT" ] && nodeport_count=$((nodeport_count + 1))
[ -n "$M1_PORT" ] && nodeport_count=$((nodeport_count + 1))
[ -n "$M2_PORT" ] && nodeport_count=$((nodeport_count + 1))

echo "Wrote inventory to $OUT_FILE"
echo "control=${control_count} workers=${worker_count} nodeport_services=${nodeport_count}"
