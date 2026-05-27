#!/usr/bin/env bash
set -euo pipefail

# Idempotent: append a public key into /home/docker/.ssh/authorized_keys on all pods
# Usage: ./loop_install_pubkey.sh [-n namespace] [-p pubkey_path] [-k kc_cmd]

NAMESPACE="weblogic"
KC_CMD="${KC_CMD:-kc}"
PUBKEY_PATH="${PUBKEY_PATH:-${HOME}/.ssh/id_ed25519_docker.pub}"

usage(){
  cat <<EOF
Usage: $0 [-n namespace] [-p pubkey_path] [-k kc_cmd]
  -n namespace   Kubernetes namespace (default: weblogic)
  -p pubkey_path Public key file to install (default: ~/.ssh/id_ed25519_docker.pub)
  -k kc_cmd      kubectl wrapper (default: kc)
EOF
  exit 1
}

while getopts ":n:p:k:" opt; do
  case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    p) PUBKEY_PATH="$OPTARG" ;;
    k) KC_CMD="$OPTARG" ;;
    *) usage ;;
  esac
done

if [ ! -f "$PUBKEY_PATH" ]; then
  echo "Public key not found: $PUBKEY_PATH" >&2
  exit 2
fi

echo "Using namespace=$NAMESPACE kc_cmd=$KC_CMD pubkey=$PUBKEY_PATH"

for p in $($KC_CMD get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "Processing pod: $p"
  if $KC_CMD exec -n "$NAMESPACE" "$p" -- test -d /home/docker >/dev/null 2>&1; then
    # idempotent append
    $KC_CMD exec -i -n "$NAMESPACE" "$p" -- sh -c 'mkdir -p /home/docker/.ssh && touch /home/docker/.ssh/authorized_keys && grep -qxF "$(cat /dev/stdin)" /home/docker/.ssh/authorized_keys || cat >> /home/docker/.ssh/authorized_keys' < "$PUBKEY_PATH" ||
      echo "Warning: failed to write authorized_keys into $p"
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chown -R docker:docker /home/docker || true
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chmod 700 /home/docker/.ssh || true
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chmod 600 /home/docker/.ssh/authorized_keys || true
  else
    echo "Skipping $p: /home/docker does not exist"
  fi
done

echo "Done."

