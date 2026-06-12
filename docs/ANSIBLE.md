Ansible quickstart for this repo

This README explains how to generate an Ansible inventory from your Minikube profile, bootstrap nodes (install Python) and run a simple playbook.

Files provided
- `scripts/generate_inventory.sh` and `scripts/generate_inventory.py` — generate `inventory.yaml` from `minikube -p <profile> node list`.
- `inventory.yaml` — example YAML inventory (will be overwritten by generator)
- `ansible/bootstrap_nodes.yml` — playbook that installs Python (if missing) and runs a connectivity test.
- `ansible/ansible.cfg` — convenience config for running the playbook from the `ansible/` folder.

Usage

1) Generate inventory (adjust MK_PRF or ANSIBLE_SSH_KEY if needed):

```bash
chmod +x scripts/generate_inventory.sh scripts/generate_inventory.py
MK_PRF=wlcluster ./scripts/generate_inventory.py
# or
MK_PRF=wlcluster ./scripts/generate_inventory.sh
```

2) Inspect `inventory.yaml` and adjust keys or users if needed.

3) Run the bootstrap playbook (from repo root):

```bash
# from repo root
ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml
```

or using the packaged ansible config (from ansible/ directory):

```bash
cd ansible
ansible-playbook bootstrap_nodes.yml
```

What the playbook does
- `control` / `workers`: bootstrap runs with `become: yes`, installs Python 3 if missing and then verifies connectivity.
- `weblogic_ssh`: bootstrap does **not** force `become`, because these SSH targets may not have interactive sudo configured. It first uses an unprivileged raw check and only uses `sudo -n` when passwordless sudo is available.
- Verification then runs `ping` and creates `/tmp/ansible_bootstrapped` for both target types.

Notes/Comments
- Inventory entries use `ansible_user: docker` and `ansible_ssh_private_key_file` by default. Adjust as necessary for your environment.
- The playbook uses `raw` to bootstrap Python because Ansible requires Python on the remote hosts to run modules.
- For Minikube container nodes: ensure SSH access is possible (we prepared SSH in the dev images).
- For WebLogic SSH pods, the current `images/wls-dev/Dockerfile` now installs `python3` and configures passwordless sudo for `docker`. If your pods still run an older image, rebuild and roll them out again before retesting.

Refresh the WebLogic dev image after this change

```bash
./prepare_docker/build_and_deploy_wls_dev.sh
```

Quick workaround if you only want to bootstrap the Minikube nodes first:

```bash
ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml --limit 'control:workers'
```

Helper scripts
--------------
- `prepare_docker/pd/deploy-ssh-keys.sh` — creates `/home/docker/.ssh` inside Minikube node containers, copies `setup_user.sh` and your public key, and prepares hostPath PV directories (chown to uid 1000).
- `prepare_docker/fix_wls_pods.sh` — convenience script to restart deployments and idempotently ensure the public key is present in each pod's `/home/docker/.ssh/authorized_keys`.

If you want, I can also add more example tasks (installing Java, copying WebLogic binaries, etc.).

