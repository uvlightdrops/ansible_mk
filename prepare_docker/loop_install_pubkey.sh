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

# parse common options (-n -k) and then handle -p locally
source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

OPTIND=1
while getopts ":p:" opt; do
  case "$opt" in
    p) PUBKEY_PATH="$OPTARG" ;;
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
    echo "- /home/docker exists in $p"
    # Try a conservative idempotent append using stdin; if that fails, fall back to kubectl cp method
    if $KC_CMD exec -i -n "$NAMESPACE" "$p" -- sh -c 'mkdir -p /home/docker/.ssh && touch /home/docker/.ssh/authorized_keys && grep -qxF "$(cat /dev/stdin)" /home/docker/.ssh/authorized_keys || cat >> /home/docker/.ssh/authorized_keys' < "$PUBKEY_PATH"; then
      echo "- appended pubkey via stdin into $p"
    else
      echo "- stdin append failed, trying kubectl cp fallback for $p"
      # copy pubkey to /tmp and append inside the pod (avoids quoting issues)
      tmp_remote="/tmp/$(basename $PUBKEY_PATH).$$"
      if $KC_CMD cp "$PUBKEY_PATH" -n "$NAMESPACE" "$p:$tmp_remote" >/dev/null 2>&1; then
        echo "- copied pubkey to $p:$tmp_remote"
        # append if not present
        if $KC_CMD exec -n "$NAMESPACE" "$p" -- sh -c 'mkdir -p /home/docker/.ssh && touch /home/docker/.ssh/authorized_keys && grep -qxFf "$1" /home/docker/.ssh/authorized_keys || cat "$1" >> /home/docker/.ssh/authorized_keys' -- "$tmp_remote"; then
          echo "- appended pubkey from $tmp_remote into authorized_keys"
        else
          echo "Warning: fallback append failed for $p" >&2
        fi
        # cleanup
        $KC_CMD exec -n "$NAMESPACE" "$p" -- rm -f "$tmp_remote" || true
      else
        echo "Warning: failed to copy pubkey into pod $p" >&2
      fi
    fi

    # fix ownership/permissions conservatively
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chown -R docker:docker /home/docker || true
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chmod 700 /home/docker/.ssh || true
    $KC_CMD exec -n "$NAMESPACE" "$p" -- chmod 600 /home/docker/.ssh/authorized_keys || true
  else
    echo "Skipping $p: /home/docker does not exist (init may have failed)"
    echo "  -> check initContainer status and logs: $KC_CMD describe pod -n $NAMESPACE $p" >&2
  fi
done


echo "Done."

