# AGENTS.md – AI Agent Guide

## Big Picture

This repo provisions a **WebLogic-on-Kubernetes dev environment** running inside a local **Minikube** cluster (profile `wlcluster`, 3–4 nodes).  
Three layers work together:

1. **Minikube nodes** (Docker containers) – prepared via `prepare_docker/pd.sh -a assemble --level full`
2. **Kubernetes workloads** (`k8s/`) – one WebLogic Admin Server pod + two Managed Server pods + optional test DB, all in namespace `weblogic`
3. **Ansible** (`ansible/`, `k8s_weblogic/`) – bootstraps Python on nodes, then deploys the WebLogic Operator and Domain CR

The shell orchestrator `prepare_docker/pd.sh` is the primary ops entrypoint. The Python package `prepare_docker_py/` remains available for supplemental workflows.

---

## Critical Environment Setup

```bash
# The `kc` alias/tool wraps minikube kubectl for profile wlcluster
alias kc="minikube -p wlcluster kubectl --"
# OR set via env (used by prepare_docker_py)
export KC_CMD="minikube -p wlcluster kubectl --"
export MK_PRF=wlcluster
export KUBECONFIG="$(minikube -p wlcluster kubeconfig)"
```

All Python CLI invocations require `PYTHONPATH=.` unless run as a module:
```bash
PYTHONPATH=. python3 prepare_docker_py/cli.py <subcommand>
```

---

## Developer Workflows

### Initial node preparation (once per cluster)
```bash
./prepare_docker/pd.sh -a assemble --level full  # node SSH prep + configmap + rollout + pubkeys + verify
# or only deploy SSH keys on Minikube nodes:
bash prepare_docker/pd/deploy-ssh-keys.sh
```

### Generate Ansible inventory from live cluster
```bash
MK_PRF=wlcluster ./scripts/generate_inventory.py   # overwrites inventory.yaml
```

### Bootstrap nodes (installs Python) and verify connectivity
```bash
ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml
# or from ansible/ dir:  ansible-playbook bootstrap_nodes.yml
```

### Deploy WebLogic Operator + Domain
```bash
ansible-galaxy collection install kubernetes.core
ansible-playbook k8s_weblogic/deploy_weblogic.yml   # uses group_vars/all.yml
```

### Day-2 pod operations (Shell — `pd.sh`)
```bash
# Einzelnen Pod prüfen
./prepare_docker/pd.sh --pod wls-managed-1-0 diagnose
./prepare_docker/pd.sh --pod wls-managed-1-0 check ssh
./prepare_docker/pd.sh --pod wls-managed-1-0 check nodeport

# Alle Pods
./prepare_docker/pd.sh -a diagnose
./prepare_docker/pd.sh -a assemble --level pod   # nur pubkeys verteilen
./prepare_docker/pd.sh -a down --level scale-down -y
```

### Day-2 pod operations (Python CLI)
```bash
python3 prepare_docker_py/cli.py restart -n weblogic
python3 prepare_docker_py/cli.py get-pod -n weblogic -l app=wls-admin
python3 prepare_docker_py/cli.py install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker
python3 prepare_docker_py/cli.py loop-test-ssh 192.168.58.2 --ports 30222,30223,30224,30225 -k ~/.ssh/id_ed25519_docker
```

### Update gen-ssh-keys ConfigMap after script change
```bash
kubectl create configmap gen-ssh-keys-script \
  --from-file=prepare_docker/gen-ssh-keys.sh -n weblogic --dry-run=client -o yaml \
  > k8s/gen-ssh-keys-config.yaml
kc apply -f k8s/gen-ssh-keys-config.yaml
kc rollout restart deployment/wls-admin -n weblogic
kc rollout restart statefulset/wls-managed-1 -n weblogic
kc rollout restart statefulset/wls-managed-2 -n weblogic
kc rollout restart statefulset/wls-managed-3 -n weblogic
```

### Log a change to HISTORY.md
```bash
python3 prepare_docker_py/cli.py log -m "describe what you changed"
```

---

## Key Conventions

- **SSH is Minikube-only**: Pod-SSH (`docker` + `~/.ssh/id_ed25519_docker`) gilt nur fuer den Minikube-Dev-Pfad.
- **NodePorts for SSH (Minikube only)**: 30222 (wls-admin), 30223 (wls-managed-1), 30224 (wls-managed-2), 30225 (wls-managed-3)
- **Managed Server topology**: `wls-managed-1`, `wls-managed-2` and `wls-managed-3` are separate `StatefulSet`s with one replica each; this gives stable pod names/DNS for manually defined WebLogic server identities
- **PV hostPath**: `/mnt/weblogic/pv-home`, chowned to uid/gid `1000`; storage class `manual`
- **Standard deploy manifests are SSH-free** – `k8s/deploy-wls-*.yaml` are Kubernetes-only defaults
- **Minikube SSH deploy manifests live in overlay** – `k8s/overlays/minikube/deploy-wls-*.yaml`
- **Manual no-operator manifests live in overlay** – `k8s/overlays/manual/deploy-wls-*.yaml`
- **`k8s/ubuntu-wls-deployments.yaml` is deprecated** – use split manifests + overlays
- **`k8s/pvc.yaml` is deprecated** – use `k8s/pvc-weblogic-home.yaml`
- All central Ansible variables live in `group_vars/all.yml` (`namespace`, `weblogic_image`, `pv_host_path`, etc.); secrets should be stored in Ansible Vault
- `prepare_docker_py/kc.py` resolves `kc` via `KC_CMD` env var; always set this before running the CLI against a non-default cluster

---

## Key Files

| File/Dir | Purpose |
|---|---|
| `group_vars/all.yml` | Single source of truth for namespace, domain, image, PV config |
| `k8s/` | All K8s manifests (split, current) |
| `prepare_docker_py/cli.py` | Main Python CLI entry point |
| `tools/pd-secondary` | Secondary wrapper for Python CLI |
| `prepare_docker_py/kc.py` | Thin subprocess wrapper for `kubectl`/`kc` |
| `ansible/bootstrap_nodes.yml` | Ensures Python is present, runs ping |
| `k8s_weblogic/deploy_weblogic.yml` | Deploys Operator + Domain CR via `kubernetes.core` |
| `prepare_docker/pd/deploy-ssh-keys.sh` | One-time Minikube node SSH + PV preparation (aufgerufen via `pd.sh -a assemble --level full`) |
| `docs/HISTORY.md` | Timestamped change log (append via CLI) |
| `docs/WEBLOGIC_DEPLOYMENT.md` | Full deployment walkthrough + troubleshooting |

