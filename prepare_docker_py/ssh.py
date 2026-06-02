import subprocess
from typing import Optional


def pub_from_priv(priv_path: str, out_path: Optional[str] = None) -> str:
    """Generate public key string from private key file using ssh-keygen -y."""
    cmd = ["ssh-keygen", "-y", "-f", priv_path]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    pub = r.stdout.decode('utf-8').strip()
    if out_path:
        with open(out_path, 'w') as f:
            f.write(pub + '\n')
    return pub


def test_ssh(node_ip: str, port: int, user: str, key_path: str, timeout: int = 5) -> subprocess.CompletedProcess:
    ssh_cmd = [
        "ssh",
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", f"ConnectTimeout={timeout}",
        "-i", key_path,
        "-p", str(port),
        f"{user}@{node_ip}",
        "echo SSH_OK"
    ]
    return subprocess.run(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

