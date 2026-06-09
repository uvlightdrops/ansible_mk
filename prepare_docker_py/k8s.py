from .kc import KC
from typing import List, Optional


class K8sOps:
    def __init__(self, kc: Optional[KC] = None):
        self.kc = kc or KC()

    def apply(self, manifest_path: str):
        return self.kc.run(["apply", "-f", manifest_path])

    def get_pod_name(self, namespace: str = "weblogic", label: str = "app=wls-admin") -> Optional[str]:
        try:
            out = self.kc.run_output(["get", "pods", "-n", namespace, "-l", label, "-o", "jsonpath={.items[0].metadata.name}"])
            return out
        except Exception:
            return None

    def get_pods(self, namespace: str = "weblogic", label: str = "app=wls-admin") -> List[str]:
        try:
            out = self.kc.run_output(["get", "pods", "-n", namespace, "-l", label, "-o", "jsonpath={.items[*].metadata.name}"])
            return out.split() if out else []
        except Exception:
            return []

    def exec(self, namespace: str, pod: str, container: Optional[str], cmd: str, input_data: Optional[bytes] = None):
        args = ["exec", "-n", namespace, pod]
        if container:
            args += ["-c", container]
        args += ["--", "sh", "-c", cmd]
        return self.kc.run(args, input=input_data)

    def cp(self, src: str, namespace: str, pod: str, dest: str):
        # local src to pod dest
        return self.kc.run(["cp", src, f"{namespace}/{pod}:{dest}"])

    def logs(self, namespace: str, pod: str, container: Optional[str] = None, tail: int = 200):
        args = ["logs", "-n", namespace, pod, "--tail", str(tail)]
        if container:
            args += ["-c", container]
        return self.kc.run(args)

    def rollout_restart(self, namespace: str, label_selector: Optional[str] = None):
        # restart deployments and statefulsets with label selector if provided
        if label_selector:
            # best effort: restart both workload types by label
            self.kc.run(["rollout", "restart", "deployment", "-n", namespace, "-l", label_selector], check=False)
            return self.kc.run(["rollout", "restart", "statefulset", "-n", namespace, "-l", label_selector], check=False)
        else:
            self.kc.run(["rollout", "restart", "deployment", "-n", namespace, "--all"], check=False)
            return self.kc.run(["rollout", "restart", "statefulset", "-n", namespace, "--all"], check=False)

