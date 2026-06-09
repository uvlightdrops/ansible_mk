# HISTORY

This file records commands executed and outputs reported by the operator during the preparation and debugging of the Minikube / WebLogic environment.

Entries are appended as timestamped paragraphs. Use the helper CLI to add entries:

Example:

    python3 prepare_docker_py/cli.py log -m "kc exec ... -> output..."

## Recent commands and reported outputs

### Command
kc exec -i -n weblogic $POD -c wls-admin -- sh -c 'grep -Fxf /dev/stdin /home/docker/.ssh/authorized_keys >/dev/null && echo FOUND || echo NOTFOUND' < /tmp/my.pub

Output (user cancelled before full output was posted)


### Command
kc exec -n weblogic $POD -c wls-admin -- sed -n '1,20p' /home/docker/.ssh/authorized_keys || true

Output
sed: can't read /home/docker/.ssh/authorized_keys: Permission denied
command terminated with exit code 2


### Command
kc debug -n weblogic pod/$POD -it --image=alpine --target=wls-admin -- sh -c 'echo "LS:"; ls -ln /home/docker /home/docker/.ssh /home/docker/.ssh/authorized_keys || true; echo; echo "STAT:"; stat -c "%U:%G %a %n" /home/docker/.ssh/authorized_keys 2>/dev/null || true; echo; echo "CAT:"; cat /home/docker/.ssh/authorized_keys 2>/dev/null || true'

Output
Defaulting debug container name to debugger-xf9m2.
LS:

STAT:

CAT:


### Command
kc cp /tmp/my.pub -n weblogic $POD:/tmp/my.pub && kc debug -n weblogic pod/$POD -it --image=alpine --target=wls-admin -- sh -c 'mkdir -p /home/docker/.ssh; cat /tmp/my.pub >> /home/docker/.ssh/authorized_keys; chown docker:docker /home/docker/.ssh/authorized_keys; chmod 600 /home/docker/.ssh/authorized_keys; rm -f /tmp/my.pub'

Output
Defaulted container "wls-admin" out of: wls-admin, debugger-7zkjw (ephem), debugger-4x24b (ephem), debugger-4vzzw (ephem), gen-ssh-keys (init)
... (shortened)
cat: can't open '/tmp/my.pub': No such file or directory
chown: unknown user/group docker:docker


### Command
kc exec -n weblogic $POD -c wls-admin -- sh -c 'grep -E "AuthorizedKeysFile|PubkeyAuthentication|PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null || true; ps aux | grep [s]shd || true; test -f /var/log/auth.log && tail -n 200 /var/log/auth.log || true'

Output
#PubkeyAuthentication yes
#AuthorizedKeysFile	.ssh/authorized_keys .ssh/authorized_keys2
#PasswordAuthentication yes
# PasswordAuthentication.  Depending on your PAM configuration,
# PAM authentication, then enable this but set PasswordAuthentication
ubuntu         1  0.0  0.0  12028  8132 ?        Ss   12:05   0:00 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
ubuntu        90  0.0  0.0   2808  1952 ?        Ss   12:27   0:00 sh -c grep -E "AuthorizedKeysFile|PubkeyAuthentication|PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null || true; ps aux | grep [s]shd || true; test -f /var/log/auth.log && tail -n 200 /var/log/auth.log || true

### Build / Deploy Befehle (kopierbar)

# Variante A: build direkt in minikube (multi-node safe)
minikube -p wlcluster image build -t wls-dev:1.3 images/wls-dev

# Variante B: lokal build + load
docker build -t wls-dev:1.3 images/wls-dev
minikube -p wlcluster image load wls-dev:1.3

# dann rollout restart
kc rollout restart deployment/wls-admin -n weblogic
kc rollout restart deployment/wls-managed-1 -n weblogic
kc rollout restart deployment/wls-managed-2 -n weblogic
