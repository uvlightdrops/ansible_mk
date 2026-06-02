import os
import shlex
import subprocess
from typing import List, Optional


class KC:
    def __init__(self, cmd: Optional[str] = None):
        # KC_CMD must be set in environment or default to 'kc'
        self.cmd = cmd or os.environ.get("KC_CMD", "kc")
        # split into argv form
        self._base = shlex.split(self.cmd)

    def run(self, args: List[str], capture: bool = False, check: bool = True, input: Optional[bytes] = None):
        cmd = self._base + args
        if capture:
            return subprocess.run(cmd, input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)
        else:
            return subprocess.run(cmd, input=input, check=check)

    def run_output(self, args: List[str]) -> str:
        r = self.run(args, capture=True, check=True)
        return r.stdout.decode('utf-8').strip()

