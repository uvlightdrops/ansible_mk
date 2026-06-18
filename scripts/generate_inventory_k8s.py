#!/usr/bin/env python3
"""
Generate inventory.yaml from a real Kubernetes cluster (kubectl context).

Usage examples:
  ANSIBLE_SSH_KEY=~/.ssh/id_ed25519 ./scripts/generate_inventory_k8s.py
  KC_CMD="kubectl --context prod-cluster" ./scripts/generate_inventory_k8s.py -n wl

Environment variables:
  KC_CMD                 kubectl command (default: kubectl)
  ANSIBLE_SSH_KEY        private key path (default: ~/.ssh/id_ed25519)
  ANSIBLE_SSH_USER       SSH user for nodes/pods (default: docker)
  ANSIBLE_NODEPORT_HOST  force ansible_host for weblogic_ssh entries
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_FILE = REPO_ROOT / "inventory.yaml"
DEFAULT_KEY = str(Path.home() / ".ssh" / "id_ed25519")
DEFAULT_KC_CMD = "kubectl"

# Service-name -> inventory-host mapping
NODEPORT_SERVICE_MAP = {
    "wls-admin-ssh-nodeport": "wls-admin-node",
    "wls-managed-1-ssh-nodeport": "wls-managed-1-node",
    "wls-managed-2-ssh-nodeport": "wls-managed-2-node",
}


def run_json(kc_cmd: str, args: List[str]) -> dict:
    cmd = shlex.split(kc_cmd) + args + ["-o", "json"]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
        return json.loads(out)
    except subprocess.CalledProcessError as exc:
        print(f"Command failed: {' '.join(cmd)}\n{exc.output}", file=sys.stderr)
        raise
    except FileNotFoundError:
        print(f"kubectl command not found: {kc_cmd}", file=sys.stderr)
        raise


def pick_node_ip(status: dict) -> Optional[str]:
    addresses = status.get("addresses", [])
    preferred = ["InternalIP", "ExternalIP", "Hostname"]
    by_type = {entry.get("type"): entry.get("address") for entry in addresses}
    for addr_type in preferred:
        ip = by_type.get(addr_type)
        if ip:
            return ip
    return None


def is_control_plane(labels: dict) -> bool:
    return (
        "node-role.kubernetes.io/control-plane" in labels
        or "node-role.kubernetes.io/master" in labels
    )


def collect_nodes(nodes_obj: dict) -> Tuple[List[Tuple[str, str]], List[Tuple[str, str]]]:
    control: List[Tuple[str, str]] = []
    workers: List[Tuple[str, str]] = []

    for item in nodes_obj.get("items", []):
        meta = item.get("metadata", {})
        status = item.get("status", {})
        labels = meta.get("labels", {})

        name = meta.get("name")
        ip = pick_node_ip(status)
        if not name or not ip:
            continue

        if is_control_plane(labels):
            control.append((name, ip))
        else:
            workers.append((name, ip))

    return control, workers


def collect_nodeports(svc_obj: dict) -> Dict[str, int]:
    ports: Dict[str, int] = {}
    for item in svc_obj.get("items", []):
        name = item.get("metadata", {}).get("name", "")
        inv_host = NODEPORT_SERVICE_MAP.get(name)
        if not inv_host:
            continue

        for port in item.get("spec", {}).get("ports", []):
            node_port = port.get("nodePort")
            if node_port:
                ports[inv_host] = int(node_port)
                break
    return ports


def write_group_hosts(fh, hosts: List[Tuple[str, str]], key_path: str, user: str) -> None:
    if not hosts:
        fh.write("        # no hosts detected\n")
        return
    for name, ip in hosts:
        fh.write(f"        {name}:\n")
        fh.write(f"          ansible_host: {ip}\n")
        fh.write(f"          ansible_user: {user}\n")
        fh.write(f"          ansible_ssh_private_key_file: {key_path}\n")


def write_inventory(
    out_file: Path,
    key_path: str,
    user: str,
    control: List[Tuple[str, str]],
    workers: List[Tuple[str, str]],
    nodeport_host: str,
    nodeports: Dict[str, int],
) -> None:
    with out_file.open("w", encoding="utf-8") as fh:
        fh.write("all:\n")
        fh.write("  children:\n")

        fh.write("    control:\n")
        fh.write("      hosts:\n")
        write_group_hosts(fh, control, key_path, user)

        fh.write("    workers:\n")
        fh.write("      hosts:\n")
        write_group_hosts(fh, workers, key_path, user)

        fh.write("    weblogic_ssh:\n")
        fh.write("      hosts:\n")
        if not nodeports:
            fh.write("        # no matching NodePort services found in namespace\n")
        else:
            for host in sorted(nodeports):
                fh.write(f"        {host}:\n")
                fh.write(f"          ansible_host: {nodeport_host}\n")
                fh.write(f"          ansible_port: {nodeports[host]}\n")
                fh.write(f"          ansible_user: {user}\n")
                fh.write(f"          ansible_ssh_private_key_file: {key_path}\n")

        fh.write("\n# You can add group_vars under group_vars/ directory or edit this file to add vars.\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Ansible inventory from Kubernetes")
    parser.add_argument("-n", "--namespace", default="wl", help="namespace for NodePort services")
    parser.add_argument("-o", "--out-file", default=str(DEFAULT_OUT_FILE), help="output inventory path")
    parser.add_argument("--kc-cmd", default=os.environ.get("KC_CMD", DEFAULT_KC_CMD), help="kubectl command")
    parser.add_argument("--ssh-key", default=os.environ.get("ANSIBLE_SSH_KEY", DEFAULT_KEY), help="ssh private key path")
    parser.add_argument("--ssh-user", default=os.environ.get("ANSIBLE_SSH_USER", "docker"), help="ssh user")
    parser.add_argument(
        "--nodeport-host",
        default=os.environ.get("ANSIBLE_NODEPORT_HOST"),
        help="override ansible_host used for weblogic_ssh entries",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_file = Path(args.out_file).expanduser().resolve()
    key_path = str(Path(args.ssh_key).expanduser())

    print(f"Reading Kubernetes nodes via: {args.kc_cmd}")
    nodes_obj = run_json(args.kc_cmd, ["get", "nodes"])

    print(f"Reading services in namespace '{args.namespace}'")
    svc_obj = run_json(args.kc_cmd, ["get", "svc", "-n", args.namespace])

    control, workers = collect_nodes(nodes_obj)
    if not control and not workers:
        print("No usable nodes found (missing node IPs).", file=sys.stderr)
        return 1

    nodeports = collect_nodeports(svc_obj)

    default_nodeport_host = None
    if control:
        default_nodeport_host = control[0][1]
    elif workers:
        default_nodeport_host = workers[0][1]

    nodeport_host = args.nodeport_host or default_nodeport_host
    if not nodeport_host:
        print("Could not determine nodeport host IP.", file=sys.stderr)
        return 1

    write_inventory(
        out_file=out_file,
        key_path=key_path,
        user=args.ssh_user,
        control=control,
        workers=workers,
        nodeport_host=nodeport_host,
        nodeports=nodeports,
    )

    print(f"Wrote inventory to {out_file}")
    print(f"control={len(control)} workers={len(workers)} nodeport_services={len(nodeports)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

