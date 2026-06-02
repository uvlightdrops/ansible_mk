from typing import List
from .kc import KC
from .ssh import pub_from_priv, test_ssh


def loop_check_home(namespace: str = 'weblogic', label: str = 'app=wls-admin') -> int:
    kc = KC()
    # get pods
    pods_out = kc.run_output(['get', 'pods', '-n', namespace, '-l', label, '-o', 'jsonpath={.items[*].metadata.name}'])
    pods = pods_out.split() if pods_out else []
    if not pods:
        print('no pods')
        return 1
    for p in pods:
        print('---', p, '---')
        r = kc.run(['exec', '-n', namespace, p, '--', 'sh', '-c', "ls -ld /home/docker /home/docker/.ssh /home/docker/.ssh/authorized_keys 2>/dev/null || true"], capture=True, check=False)
        print(r.stdout.decode('utf-8'))
    return 0


def loop_install_pubkey(namespace: str = 'weblogic', label: str = 'app=wls-admin', container: str = 'wls-admin', privkey: str = '~/.ssh/id_ed25519_docker') -> int:
    kc = KC()
    pods_out = kc.run_output(['get', 'pods', '-n', namespace, '-l', label, '-o', 'jsonpath={.items[*].metadata.name}'])
    pods = pods_out.split() if pods_out else []
    if not pods:
        print('no pods')
        return 1
    pub = pub_from_priv(privkey)
    for p in pods:
        print('installing pubkey into', p)
        # use exec with stdin
        kc.run(['exec', '-i', '-n', namespace, p, '-c', container, '--', 'sh', '-c', "mkdir -p /home/docker/.ssh && grep -Fxf /dev/stdin /home/docker/.ssh/authorized_keys >/dev/null 2>&1 || cat >> /home/docker/.ssh/authorized_keys; chown -R docker:docker /home/docker; chmod 700 /home/docker/.ssh; chmod 600 /home/docker/.ssh/authorized_keys"], input=pub.encode('utf-8'))
    return 0


def loop_test_ssh(node_ip: str, ports: List[int], user: str = 'docker', key: str = '~/.ssh/id_ed25519_docker') -> int:
    rc = 0
    for port in ports:
        print('Testing', node_ip, port)
        res = test_ssh(node_ip, port, user, key)
        out = res.stdout.decode('utf-8', errors='ignore').strip()
        err = res.stderr.decode('utf-8', errors='ignore').strip()
        print('-> stdout:', out)
        print('-> stderr:', err)
        if res.returncode != 0:
            rc = res.returncode
    return rc

