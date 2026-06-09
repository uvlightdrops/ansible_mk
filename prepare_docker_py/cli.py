#!/usr/bin/env python3
import argparse
import sys
import os
# when executing the script directly (python3 prepare_docker_py/cli.py)
# ensure the parent directory is on sys.path so `import prepare_docker_py...` works
_here = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_here)
if _root not in sys.path:
    sys.path.insert(0, _root)

# use absolute imports so the script can be executed directly
from prepare_docker_py.k8s import K8sOps
from prepare_docker_py.kc import KC
from prepare_docker_py.ssh import pub_from_priv, test_ssh
from prepare_docker_py.loops import loop_check_home, loop_install_pubkey, loop_test_ssh
from prepare_docker_py.history import append_entry


def cmd_apply(args):
    k = K8sOps()
    k.apply(args.manifest)


def cmd_restart(args):
    k = K8sOps()
    k.rollout_restart(args.namespace)


def cmd_get_pod(args):
    k = K8sOps()
    pod = k.get_pod_name(args.namespace, args.label)
    if pod:
        print(pod)
        return 0
    return 1


def cmd_install_pubkey(args):
    k = K8sOps()
    pod = k.get_pod_name(args.namespace, args.label)
    if not pod:
        print('no pod')
        return 1
    pub = pub_from_priv(args.key)
    # pipe pub into pod and append idempotent
    kc = KC()
    kc.run(["exec", "-n", args.namespace, pod, "-c", args.container, "--", "sh", "-c",
            "mkdir -p /home/docker/.ssh && grep -Fxf /dev/stdin /home/docker/.ssh/authorized_keys >/dev/null 2>&1 || cat >> /home/docker/.ssh/authorized_keys; chown -R docker:docker /home/docker; chmod 700 /home/docker/.ssh; chmod 600 /home/docker/.ssh/authorized_keys"], input=pub.encode('utf-8'))
    print('installed')


def cmd_test_ssh(args):
    res = test_ssh(args.node_ip, args.port, args.user, args.key)
    sys.stdout.buffer.write(res.stdout)
    sys.stderr.buffer.write(res.stderr)
    return res.returncode


def cmd_loop_check_home(args):
    return loop_check_home(namespace=args.namespace, label=args.label)


def cmd_loop_install_pubkey(args):
    return loop_install_pubkey(namespace=args.namespace, label=args.label, container=args.container, privkey=args.key)


def cmd_loop_test_ssh(args):
    ports = [int(p) for p in args.ports.split(',')] if args.ports else [args.port]
    return loop_test_ssh(node_ip=args.node_ip, ports=ports, user=args.user, key=args.key)


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers()

    a = sub.add_parser('apply')
    a.add_argument('manifest')
    a.set_defaults(func=cmd_apply)

    r = sub.add_parser('restart')
    r.add_argument('-n', '--namespace', default='weblogic')
    r.set_defaults(func=cmd_restart)

    g = sub.add_parser('get-pod')
    g.add_argument('-n', '--namespace', default='weblogic')
    g.add_argument('-l', '--label', default='app=wls-admin')
    g.set_defaults(func=cmd_get_pod)

    i = sub.add_parser('install-pubkey')
    i.add_argument('-n', '--namespace', default='weblogic')
    i.add_argument('-l', '--label', default='app=wls-admin')
    i.add_argument('-c', '--container', default='wls-admin')
    i.add_argument('-k', '--key', default='~/.ssh/id_ed25519_docker')
    i.set_defaults(func=cmd_install_pubkey)

    t = sub.add_parser('test-ssh')
    t.add_argument('node_ip')
    t.add_argument('-p', '--port', type=int, default=30222)
    t.add_argument('-u', '--user', default='docker')
    t.add_argument('-k', '--key', default='~/.ssh/id_ed25519_docker')
    t.set_defaults(func=cmd_test_ssh)

    lc = sub.add_parser('loop-check-home')
    lc.add_argument('-n', '--namespace', default='weblogic')
    lc.add_argument('-l', '--label', default='app=wls-admin')
    lc.set_defaults(func=cmd_loop_check_home)

    li = sub.add_parser('loop-install-pubkey')
    li.add_argument('-n', '--namespace', default='weblogic')
    li.add_argument('-l', '--label', default='app=wls-admin')
    li.add_argument('-c', '--container', default='wls-admin')
    li.add_argument('-k', '--key', default='~/.ssh/id_ed25519_docker')
    li.set_defaults(func=cmd_loop_install_pubkey)

    lt = sub.add_parser('loop-test-ssh')
    lt.add_argument('node_ip')
    lt.add_argument('-p', '--port', type=int, default=30222)
    lt.add_argument('--ports', help='comma separated ports, e.g. 30222,30223')
    lt.add_argument('-u', '--user', default='docker')
    lt.add_argument('-k', '--key', default='~/.ssh/id_ed25519_docker')
    lt.set_defaults(func=cmd_loop_test_ssh)

    lg = sub.add_parser('log')
    lg.add_argument('-m', '--message', help='message to append to HISTORY.md; if omitted, reads from stdin')
    lg.set_defaults(func=lambda args: (append_entry(args.message or sys.stdin.read()), 0)[1])

    args = p.parse_args(argv)
    if not hasattr(args, 'func'):
        p.print_help()
        return 1
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())

