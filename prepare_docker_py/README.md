prepare_docker_py

Kurz: kleine Python toolchain als Ersatz für die bash helpers.

Usage examples:

# apply a manifest
python3 prepare_docker_py/cli.py apply k8s/weblogic-authorized-keys.yaml

# restart rollouts
python3 prepare_docker_py/cli.py restart -n weblogic

# get pod name
python3 prepare_docker_py/cli.py get-pod -n weblogic -l app=wls-admin

# install public key (reads private and pipes pub)
python3 prepare_docker_py/cli.py install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker

# test ssh
python3 prepare_docker_py/cli.py test-ssh 192.168.58.2 -p 30222 -u docker -k ~/.ssh/id_ed25519_docker

Additional helpers (looping / batch checks)

# check /home/docker and .ssh in all pods matching a label
python3 prepare_docker_py/cli.py loop-check-home -n weblogic -l app=wls-admin

# install your public key into all matching pods (reads private and pipes pub)
python3 prepare_docker_py/cli.py loop-install-pubkey -n weblogic -l app=wls-admin -k ~/.ssh/id_ed25519_docker

# test SSH to multiple NodePorts (comma separated)
python3 prepare_docker_py/cli.py loop-test-ssh 192.168.58.2 --ports 30222,30223 -k ~/.ssh/id_ed25519_docker

Notes
- The CLI expects `KC_CMD` (default `kc`) available in your PATH; set via env if needed:
  export KC_CMD="minikube -p wlcluster kubectl --"
- You can run the CLI directly from the repo; if imports fail, run with PYTHONPATH=.: `PYTHONPATH=. python3 prepare_docker_py/cli.py ...`
- The code is intentionally small and synchronous; if you want parallel checks, diagnostics output or an auto-fix option, tell me which and I add it.

Fixing permissions and installing your public key (quick steps)

If SSH login as `docker` fails because the Pod's authorized_keys or ownership are wrong, run these steps (replace `$POD` and `$NODE_IP`):

1) Generate your public key from the private key and show it:
```bash
ssh-keygen -y -f ~/.ssh/id_ed25519_docker > /tmp/my.pub
cat /tmp/my.pub
```

2) Check whether the exact line exists in the Pod's authorized_keys:
```bash
kc exec -n weblogic $POD -c wls-admin -- sed -n '1,20p' /home/docker/.ssh/authorized_keys || true
kc exec -i -n weblogic $POD -c wls-admin -- sh -c 'grep -Fxf /dev/stdin /home/docker/.ssh/authorized_keys >/dev/null && echo FOUND || echo NOTFOUND' < /tmp/my.pub
```

3) If `NOTFOUND`, append idempotently and fix owner/perms:
```bash
kc exec -i -n weblogic $POD -c wls-admin -- sh -c 'mkdir -p /home/docker/.ssh && grep -Fxf /dev/stdin /home/docker/.ssh/authorized_keys >/dev/null 2>&1 || cat >> /home/docker/.ssh/authorized_keys; chown -R docker:docker /home/docker || true; chmod 700 /home/docker/.ssh; chmod 600 /home/docker/.ssh/authorized_keys' < /tmp/my.pub
```

4) If `chown` or writes are denied, run a one‑time root debug repair (creates user `docker` if missing and fixes perms):
```bash
kc debug -n weblogic pod/$POD -it --image=alpine --target=wls-admin -- sh -c "id docker >/dev/null 2>&1 || adduser -D docker 2>/dev/null || useradd -m docker; mkdir -p /home/docker/.ssh; touch /home/docker/.ssh/authorized_keys; chown -R docker:docker /home/docker || true; chmod 700 /home/docker/.ssh || true; chmod 600 /home/docker/.ssh/authorized_keys || true"
```

5) Test SSH from host (use the private key, not the .pub file):
```bash
ssh -vvv -i ~/.ssh/id_ed25519_docker -o IdentitiesOnly=yes -p 30222 docker@$NODE_IP
```

If you still see `Permission denied`, post the outputs of step 2 and the `ssh -vvv` trace and I'll suggest the next fix.

