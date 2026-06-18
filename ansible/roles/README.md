# Ansible Roles

Diese Rollen sind bewusst klein und getrennt:

- `weblogic_classic_install` – klassische WebLogic-Installation auf SSH-Hosts/VMs
- `k8s_apply_resources` – lokale Kubernetes-Manifeste anwenden
- `k8s_pod_exec` – Befehle in einen Pod per `kubectl exec` ausfuehren

Die Idee ist:

- **VMs**: weiterhin per SSH
- **Pods**: ohne SSH, ueber Kubernetes-API/`kubectl`

Siehe auch `docs/ANSIBLE_ROLES.md`.

