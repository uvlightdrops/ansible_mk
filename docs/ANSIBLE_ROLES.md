# Ansible Roles in diesem Repo

Diese Rollen trennen die zwei Welten im Projekt:

- **VM / SSH Targets**: klassische Ansible-Tasks auf Linux-Hosts
- **Kubernetes / Pods**: lokale Ausführung via `kubectl`, ohne SSH in den Cluster

## Rollen

### `weblogic_classic_install`
Kapselt die klassische WebLogic-Installation auf SSH-Zielsystemen.

Verwendet:
- Java installieren
- Verzeichnisse anlegen
- Installer kopieren
- Response-File rendern
- Silent Installer starten

Beispiel:

```yaml
- hosts: weblogic_ssh
  become: yes
  roles:
    - weblogic_classic_install
```

### `k8s_apply_resources`
Wendet Kubernetes-Manifeste lokal per `kubectl apply` an.

Beispiel:

```yaml
- hosts: localhost
  connection: local
  roles:
    - role: k8s_apply_resources
      vars:
        k8s_apply_style: files
        k8s_apply_files:
          - ../k8s/namespace.yaml
          - ../k8s/pvc-weblogic-home.yaml
```

### `k8s_pod_exec`
Führt einen Befehl in einem Pod aus, gefunden ueber ein Label-Selector.

Das ist die bevorzugte Alternative zu SSH in restriktiven Clustern.

Beispiel:

```yaml
- hosts: localhost
  connection: local
  roles:
    - role: k8s_pod_exec
      vars:
        k8s_namespace: weblogic
        k8s_pod_selector: app=wls-admin
        k8s_exec_command:
          - /bin/sh
          - -c
          - whoami
```

## Was das fuer deinen SecurityContext bedeutet

Der aktuelle SSH-basierte Pod-Ansatz in `k8s/deploy-wls-*.yaml` ist noch **nicht** mit einer strengen Restricted-Policy vereinbar, solange dort `runAsUser: 0` und SSH auf Port 22 verwendet wird.

Wenn der Cluster `allowPrivilegeEscalation: false` und `runAsNonRoot` erzwingt, solltest du fuer Pod-Administration eher `k8s_pod_exec` statt SSH verwenden.

