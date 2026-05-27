#!/usr/bin/env bash
set -euo pipefail

# Generate the gen-ssh-keys ConfigMap YAML from the local script and apply it
# Usage: ./gen_configmap_from_script.sh [-n namespace] [-s script_path] [-o out_yaml] [-k kc_cmd]

NAMESPACE="weblogic"
SCRIPT_PATH="prepare_docker/gen-ssh-keys.sh"
OUT_YAML="k8s/gen-ssh-keys-config.yaml"
KC_CMD="${KC_CMD:-kc}"

while getopts ":n:s:o:k:" opt; do
  case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    s) SCRIPT_PATH="$OPTARG" ;;
    o) OUT_YAML="$OPTARG" ;;
    k) KC_CMD="$OPTARG" ;;
    *) echo "Usage: $0 [-n namespace] [-s script_path] [-o out_yaml] [-k kc_cmd]"; exit 1 ;;
  esac
done

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Script not found: $SCRIPT_PATH" >&2
  exit 2
fi

echo "Generating ConfigMap from $SCRIPT_PATH -> $OUT_YAML (namespace: $NAMESPACE)"
kubectl create configmap gen-ssh-keys-script --from-file="$SCRIPT_PATH" -n "$NAMESPACE" --dry-run=client -o yaml > "$OUT_YAML"
echo "Applying $OUT_YAML"
$KC_CMD apply -f "$OUT_YAML"

echo "Done."

