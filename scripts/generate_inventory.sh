#!/bin/bash
set -euo pipefail

# generate_inventory.sh
# Generates an Ansible YAML inventory (inventory.yaml) from minikube node list.
# Usage:
#   MK_PRF=wlcluster ./scripts/generate_inventory.sh
# or set ANSIBLE_SSH_KEY to override default private key path.

PROFILE="${MK_PRF:-wlcluster}"
KEY_PATH="${ANSIBLE_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
OUT_FILE="$(dirname "$0")/../inventory.yaml"

echo "Generating $OUT_FILE from minikube profile '$PROFILE' (using key $KEY_PATH)"

# get lines that contain an IPv4 address: "name ip"
NODE_LINES=$(minikube -p "$PROFILE" node list 2>/dev/null | awk '/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1 " " $2}') || true

if [ -z "$NODE_LINES" ]; then
  echo "No nodes found for profile '$PROFILE'. Ensure minikube is running and profile name is correct." >&2
  exit 1
fi

# Start writing YAML
cat > "$OUT_FILE" <<EOF
all:
  hosts: {}
  children:
    control:
      hosts:
EOF

# iterate nodes: categorize control vs workers (simple heuristic: names with '-' are workers)
while read -r name ip; do
  if echo "$name" | grep -q "-"; then
    # worker, accumulate later
    WORKERS="${WORKERS}${name} ${ip}\n"
  else
    cat >> "$OUT_FILE" <<EOL
        ${name}:
          ansible_host: ${ip}
          ansible_user: docker
          ansible_ssh_private_key_file: ${KEY_PATH}
EOL
  fi
done <<< "$NODE_LINES"

# add workers group
cat >> "$OUT_FILE" <<EOF
    workers:
      hosts:
EOF

if [ -n "${WORKERS:-}" ]; then
  while read -r wname wip; do
    [ -z "$wname" ] && continue
    cat >> "$OUT_FILE" <<EOL
        ${wname}:
          ansible_host: ${wip}
          ansible_user: docker
          ansible_ssh_private_key_file: ${KEY_PATH}
EOL
  done <<< "${WORKERS}"
fi

# Add common group_vars (optional)
cat >> "$OUT_FILE" <<'EOF'

# You can set group_vars under group_vars/ or add here as needed.
# Example (uncomment and edit):
#  vars:
#    ansible_become: true
#    ansible_python_interpreter: /usr/bin/python3
EOF

echo "Wrote $OUT_FILE"

exit 0

