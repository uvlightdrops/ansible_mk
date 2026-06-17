# AGENTS.md – AI Agent Guide

## Architecture Overview

This repo provisions a **WebLogic-on-Minikube** dev cluster. Three tooling layers work together:

| Layer | Location | Purpose |
|---|---|---|
| Ansible playbooks | `ansible/`, `k8s_weblogic/` | Bootstrap nodes, deploy WebLogic Operator & Domain CR |
| Bash helper scripts | `prepare_docker/` | Build image, deploy SSH keys, fix pods, restart rollouts |
| Python CLI | `prepare_docker_py/` | Typed replacements for bash helpers (`cli.py`) |

**Data flow:** Minikube nodes (`wlcluster` profile) → SSH via NodePorts (30222/30223/30224) → Ansible inventory → Playbooks → Kubernetes manifests (`k8s/`) → WebLogic Operator → Domain CR.

## Environment Conventions

- **Minikube profile**: always `wlcluster` (4-node cluster: 1 control + 3 workers)
- **Namespace**: `weblogic` (hardcoded in most manifests and scripts)
- **kubectl alias**: `kc` = `minikube -p wlcluster kubectl --`; override via `KC_CMD` env var
- **SSH user in pods**: `docker`; key: `~/.ssh/id_ed25519_docker`
- **SSH user in dev image**: `weblogic` (password: `weblogic` in dev-only builds)

```bash
export MK_PRF=wlcluster
export KC_CMD="minikube -p wlcluster kubectl --"
```

## Key Files

- `group_vars/all.yml` — central config: namespace, domain UID, WebLogic image, PV path, passwords
- `inventory.yaml` — auto-generated; Ansible SSH targets including NodePort entries for pods
- `k8s/` — split manifests: use `deploy-wls-admin.yaml`, `deploy-wls-managed-1.yaml`, `deploy-wls-managed-2.yaml`, **not** the deprecated `ubuntu-wls-deployments.deprecated.yaml`
- `k8s/gen-ssh-keys-config.yaml` — generated from `prepare_docker/gen-ssh-keys.sh` (see below)

## Critical Workflows

### 1. Generate Ansible Inventory
```bash
MK_PRF=wlcluster ./scripts/generate_inventory.py   # or .sh variant
```

### 2. Bootstrap Nodes (installs Python via `raw`)
```bash
ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml
```

### 3. Build & Load Dev Image
```bash
# SSH_PUBKEY injected at build time (not baked permanently – use ConfigMap for runtime)
docker build -t wls-dev:1.3 images/wls-dev --build-arg SSH_PUBKEY="$(cat ~/.ssh/id_ed25519_docker.pub)"
minikube -p wlcluster image load wls-dev:1.3
# Or use the helper (reads PUBKEY, IMAGE_TAG, NAMESPACE env vars):
bash prepare_docker/build_and_deploy_wls_dev.sh
```

### 4. Regenerate SSH-Key ConfigMap After Script Changes
```bash
kubectl create configmap gen-ssh-keys-script \
  --from-file=prepare_docker/gen-ssh-keys.sh -n weblogic --dry-run=client -o yaml \
  > k8s/gen-ssh-keys-config.yaml
kc apply -f k8s/gen-ssh-keys-config.yaml
# Then restart deployments so InitContainers re-run:
kc rollout restart deployment/wls-admin deployment/wls-managed-1 deployment/wls-managed-2 -n weblogic
```

### 5. Python CLI (preferred over raw bash loops)
```bash
# Must run from repo root; if import errors occur:
PYTHONPATH=. python3 prepare_docker_py/cli.py <subcommand>

python3 prepare_docker_py/cli.py get-pod -n weblogic -l app=wls-admin
python3 prepare_docker_py/cli.py install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker
python3 prepare_docker_py/cli.py loop-test-ssh 192.168.58.2 --ports 30222,30223,30224 -k ~/.ssh/id_ed25519_docker
python3 prepare_docker_py/cli.py restart -n weblogic
```

## Project-Specific Patterns

- **Idempotent key injection**: always use `grep -Fxf /dev/stdin … || cat >> authorized_keys` pattern (see `cli.py:cmd_install_pubkey`)
- **WebLogic image**: must be set manually in `group_vars/all.yml` (`weblogic_image`); Oracle license prevents bundling
- **ConfigMap-based InitContainers**: SSH host keys and `/home/docker` setup are done by the `gen-ssh-keys.sh` InitContainer, not baked into the image
- **Passwords**: `group_vars/all.yml` contains `weblogic_admin_password: ChangeMe123!` — move to Ansible Vault for any non-throwaway use
- **`kc` tool**: `tools/kc` is a local wrapper script; add `tools/` to PATH or use `KC_CMD` env var

## Diagnostics
```bash
bash prepare_docker/collect_minikube_diagnostics.sh
kc get pods -n weblogic -o wide
kc describe pvc pvc-weblogic-home -n weblogic
kubectl logs -n weblogic <operator-pod>
```

