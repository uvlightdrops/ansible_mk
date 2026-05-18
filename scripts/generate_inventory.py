#!/usr/bin/env python3
"""
generate_inventory.py
Generate an Ansible YAML inventory (inventory.yaml) from `minikube -p <profile> node list`.
Usage:
  MK_PRF=wlcluster ANSIBLE_SSH_KEY=~/.ssh/id_ed25519 ./scripts/generate_inventory.py
If environment variables are not set, defaults are used:
  MK_PRF -> wlcluster
  ANSIBLE_SSH_KEY -> ~/.ssh/id_ed25519
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROFILE = os.environ.get("MK_PRF", "wlcluster")
KEY_PATH = os.environ.get("ANSIBLE_SSH_KEY", str(Path.home() / ".ssh" / "id_ed25519"))
OUT_FILE = Path(__file__).resolve().parents[1] / "inventory.yaml"

IP_RE = re.compile(r"(\d{1,3}(?:\.\d{1,3}){3})")


def run_minikube_list(profile: str) -> str:
    cmd = ["minikube", "-p", profile, "node", "list"]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
        return out
    except subprocess.CalledProcessError as e:
        print(f"Error running: {' '.join(cmd)}\n{e.output}", file=sys.stderr)
        raise
    except FileNotFoundError:
        print("minikube executable not found in PATH", file=sys.stderr)
        raise


def parse_node_lines(minikube_output: str):
    nodes = []
    for line in minikube_output.splitlines():
        line = line.strip()
        if not line:
            continue
        m = IP_RE.search(line)
        if not m:
            continue
        ip = m.group(1)
        # name is the first token
        parts = line.split()
        name = parts[0]
        nodes.append((name, ip))
    return nodes


def write_inventory(nodes, key_path: str, out_file: Path):
    # structure: all -> children -> control, workers
    control_entries = []
    worker_entries = []
    for name, ip in nodes:
        if "-" in name:
            worker_entries.append((name, ip))
        else:
            control_entries.append((name, ip))

    with out_file.open("w", encoding="utf-8") as f:
        f.write("all:\n")
        f.write("  children:\n")
        f.write("    control:\n")
        f.write("      hosts:\n")
        if control_entries:
            for name, ip in control_entries:
                f.write(f"        {name}:\n")
                f.write(f"          ansible_host: {ip}\n")
                f.write(f"          ansible_user: docker\n")
                f.write(f"          ansible_ssh_private_key_file: {key_path}\n")
        else:
            f.write("        # no control nodes detected\n")

        f.write("    workers:\n")
        f.write("      hosts:\n")
        if worker_entries:
            for name, ip in worker_entries:
                f.write(f"        {name}:\n")
                f.write(f"          ansible_host: {ip}\n")
                f.write(f"          ansible_user: docker\n")
                f.write(f"          ansible_ssh_private_key_file: {key_path}\n")
        else:
            f.write("        # no worker nodes detected\n")

        # Add weblogic SSH entries (NodePort-based access). Use the control node IP as the Node IP
        # and assign preconfigured NodePorts for admin and managed servers.
        f.write("    weblogic_ssh:\n")
        f.write("      hosts:\n")
        # determine node ip to reach NodePort on
        node_ip = None
        if control_entries:
            node_ip = control_entries[0][1]
        elif worker_entries:
            node_ip = worker_entries[0][1]
        else:
            node_ip = '127.0.0.1'

        # fixed NodePorts matching k8s/services-nodeports.yaml
        ports = {
            'wls-admin-node': 30222,
            'wls-managed-1-node': 30223,
            'wls-managed-2-node': 30224,
        }
        for host, port in ports.items():
            f.write(f"        {host}:\n")
            f.write(f"          ansible_host: {node_ip}\n")
            f.write(f"          ansible_port: {port}\n")
            f.write(f"          ansible_user: docker\n")
            f.write(f"          ansible_ssh_private_key_file: {key_path}\n")

        f.write("\n# You can add group_vars under group_vars/ directory or edit this file to add vars.\n")

    print(f"Wrote inventory to {out_file}")


def main():
    print(f"Generating inventory for minikube profile '{PROFILE}' (key: {KEY_PATH})")
    try:
        out = run_minikube_list(PROFILE)
    except Exception:
        sys.exit(1)

    nodes = parse_node_lines(out)
    if not nodes:
        print("No nodes found in minikube output. Aborting.", file=sys.stderr)
        sys.exit(1)

    write_inventory(nodes, KEY_PATH, OUT_FILE)


if __name__ == "__main__":
    main()

