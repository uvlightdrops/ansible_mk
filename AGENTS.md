# AGENTS.md – AI Agent Guide

## Architecture Overview

This repo provisions a **WebLogic-on-Minikube** dev cluster. Three tooling layers work together:

| Layer | Location | Purpose |
|---|---|---|
| Ansible playbooks | `ansible/`, `k8s_weblogic/` | Bootstrap nodes, deploy WebLogic Operator & Domain CR |
| Shell orchestrator | `prepare_docker/pd.sh` | Primary ops entrypoint; controls node prep, pod setup, diagnostics |
| Bash helpers | `prepare_docker/`, `prepare_docker/pd/` | Build image, deploy SSH keys, fix pods, restart rollouts |
| Python CLI | `prepare_docker_py/` | Typed alternatives for pod operations (`cli.py`) |

**Data flow:** Minikube nodes (`wlcluster` profile) → SSH via NodePorts (30222/30223/30224/30225) → Ansible inventory → Playbooks → Kubernetes manifests (`k8s/`) → WebLogic Operator → Domain CR.

## Environment Conventions

- **Minikube profile**: always `wlcluster` (4-node cluster: 1 control + 3 workers)
- **Namespace**: `weblogic` (hardcoded in most manifests and scripts)
- **kubectl alias**: `kc` = `minikube -p wlcluster kubectl --`; override via `KC_CMD` env var
- **SSH user in pods**: `docker`; key: `~/.ssh/id_ed25519_docker`
- **SSH user in dev image**: `weblogic` (password: `weblogic` in dev-only builds)
- **NodePorts for SSH**: 30222 (wls-admin), 30223 (wls-managed-1), 30224 (wls-managed-2), 30225 (wls-managed-3)

```bash
export MK_PRF=wlcluster
export KC_CMD="minikube -p wlcluster kubectl --"
export KUBECONFIG="$(minikube -p wlcluster kubeconfig)"
```

## Key Files

- `group_vars/all.yml` — central config: namespace, domain UID, WebLogic image, PV path, passwords
- `inventory.yaml` — auto-generated; Ansible SSH targets including NodePort entries for pods
- `k8s/` — split manifests: use `deploy-wls-admin.yaml`, `deploy-wls-managed-1.yaml`, `deploy-wls-managed-2.yaml`, `deploy-wls-managed-3.yaml`, **not** the deprecated `ubuntu-wls-deployments.deprecated.yaml`
- `k8s/gen-ssh-keys-config.yaml` — generated from `prepare_docker/gen-ssh-keys.sh` (see below)
- `prepare_docker/pd.sh` — primary shell orchestrator for cluster operations
- `prepare_docker/pd/` — individual operational scripts invoked by `pd.sh`

## Critical Workflows

### 1. Shell Orchestrator (primary ops entrypoint)
```bash
# Full cluster setup (node prep + configmap + pods + pubkeys + verify)
./prepare_docker/pd.sh -a assemble --level full

# Diagnose all pods
./prepare_docker/pd.sh -a diagnose

# Diagnose single pod
./prepare_docker/pd.sh --pod wls-admin-0 diagnose

# Restart all deployments/statefulsets
./prepare_docker/pd.sh -a check ssh
```

### 2. Generate Ansible Inventory
```bash
MK_PRF=wlcluster ./scripts/generate_inventory.py   # or .sh variant
```

### 3. Bootstrap Nodes (installs Python via `raw`)
```bash
ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml
```

### 4. Build & Load Dev Image
```bash
# SSH_PUBKEY injected at build time (not baked permanently – use ConfigMap for runtime)
docker build -t wls-dev:1.3 images/wls-dev --build-arg SSH_PUBKEY="$(cat ~/.ssh/id_ed25519_docker.pub)"
minikube -p wlcluster image load wls-dev:1.3
# Or use the helper (reads PUBKEY, IMAGE_TAG, NAMESPACE env vars):
bash prepare_docker/build_and_deploy_wls_dev.sh
```

### 5. Regenerate SSH-Key ConfigMap After Script Changes
```bash
kubectl create configmap gen-ssh-keys-script \
  --from-file=prepare_docker/gen-ssh-keys.sh -n weblogic --dry-run=client -o yaml \
  > k8s/gen-ssh-keys-config.yaml
kc apply -f k8s/gen-ssh-keys-config.yaml
# Then restart deployments so InitContainers re-run:
kc rollout restart deployment/wls-admin statefulset/wls-managed-1 statefulset/wls-managed-2 statefulset/wls-managed-3 -n weblogic
```

### 6. Python CLI (alternative for pod-level operations)
```bash
# Must run from repo root; if import errors occur:
PYTHONPATH=. python3 prepare_docker_py/cli.py <subcommand>

# Pod querying and key management
python3 prepare_docker_py/cli.py get-pod -n weblogic -l app=wls-admin
python3 prepare_docker_py/cli.py install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker
python3 prepare_docker_py/cli.py loop-install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker

# Batch SSH tests and home directory checks
python3 prepare_docker_py/cli.py loop-test-ssh 192.168.58.2 --ports 30222,30223,30224,30225 -k ~/.ssh/id_ed25519_docker
python3 prepare_docker_py/cli.py loop-check-home -n weblogic -l app=wls-admin

# Cluster operations
python3 prepare_docker_py/cli.py apply k8s/weblogic-authorized-keys.yaml
python3 prepare_docker_py/cli.py restart -n weblogic
python3 prepare_docker_py/cli.py log -m "describe what you changed"
```

## Project-Specific Patterns

- **Idempotent key injection**: always use `grep -Fxf /dev/stdin … || cat >> authorized_keys` pattern (see `cli.py:cmd_install_pubkey`)
- **WebLogic image**: must be set manually in `group_vars/all.yml` (`weblogic_image`); Oracle license prevents bundling
- **ConfigMap-based InitContainers**: SSH host keys and `/home/docker` setup are done by the `gen-ssh-keys.sh` InitContainer, not baked into the image
- **Passwords**: `group_vars/all.yml` contains `weblogic_admin_password: ChangeMe123!` — move to Ansible Vault for any non-throwaway use
- **`kc` tool**: `tools/kc` is a local wrapper script; add `tools/` to PATH or use `KC_CMD` env var
- **Managed Server topology**: `wls-managed-1`, `wls-managed-2`, and `wls-managed-3` are separate `StatefulSet`s with one replica each; this ensures stable pod names/DNS for manually defined WebLogic server identities
- **`pd.sh` wrapper**: wraps individual scripts in `prepare_docker/pd/` for consistent clustering operations; prefer this over direct script invocation

## Diagnostics
```bash
bash prepare_docker/collect_minikube_diagnostics.sh
kc get pods -n weblogic -o wide
kc describe pvc pvc-weblogic-home -n weblogic
kubectl logs -n weblogic <operator-pod>
```

