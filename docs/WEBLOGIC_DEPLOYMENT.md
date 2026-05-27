WebLogic Deployment (Ansible + Minikube) - Kurzangaben

Überblick
---------
Dieses Verzeichnis enthält ein Minimal‑Ansible‑Playbook und Beispielmanifeste, um den WebLogic Kubernetes Operator
und eine Domain in einer Minikube‑Umgebung (Dev) bereitzustellen.

Wichtige Dateien
----------------
- `deploy_weblogic.yml`  - Haupt‑Playbook (lokal, connection: local)
- `group_vars/all.yml`   - zentrale Variablen (Namespace, DomainUID, Image, PV‑Pfad)
- `k8s/operator.yaml`    - Platzhalter für den Operator‑Manifest (lade offiziellen Release hierher)
- `k8s/pv.yaml`          - hostPath PersistentVolume (Dev)
- `k8s/pvc-weblogic-home.yaml` - PersistentVolumeClaim (Domain home)
  (Hinweis: `k8s/pvc.yaml` ist veraltet/duplicat und wurde durch `pvc-weblogic-home.yaml` ersetzt.)
- `k8s/domain.yaml`      - Minimal Domain CR Template

Voraussetzungen
---------------
- Minikube Profil mit funktionierenden Nodes (z. B. `minikube -p wlcluster start --nodes=3`)
- `kubectl` konfiguriert oder KUBECONFIG entsprechend (z. B. `export KUBECONFIG=$(minikube -p wlcluster kubeconfig)`) 
- Ansible und die Collection `kubernetes.core` installiert:

```bash
ansible-galaxy collection install kubernetes.core
```

- WebLogic Image: Du musst ein gültiges WebLogic Image (lizenzbedingt) bereitstellen. Setze `weblogic_image` in `group_vars/all.yml`.

Kurzanleitung
-------------
1) Operator Manifest besorgen und in `k8s/operator.yaml` ablegen:

```bash
curl -L -o k8s/operator.yaml \
  https://github.com/oracle/weblogic-kubernetes-operator/releases/download/<tag>/weblogic-operator.yaml
```

2) Variablen anpassen: `group_vars/all.yml` (Admin Passwort, image etc.)

3) Kubeconfig exportieren (Minikube‑Profil):

```bash
export KUBECONFIG="$(minikube -p wlcluster kubeconfig)"
```

4) Playbook ausführen:

```bash
ansible-playbook deploy_weblogic.yml
```

5) Prüfen:

```bash
minikube -p wlcluster kubectl -- get pods -n weblogic -o wide
minikube -p wlcluster kubectl -- get domains -n weblogic
```

Hinweise
--------
- Für Entwicklung ist `hostPath` ausreichend; in Produktion nutze eine StorageClass mit dynamischer Provisionierung.
- Wenn Pods im Status `ImagePullBackOff` sind, prüfe `imagePullSecrets` oder lade das Image auf die Nodes.
- API‑Version der Domain CR (`apiVersion: weblogic.oracle/v8`) hängt vom Operator‑Release ab — gegebenenfalls anpassen.
- Sensible Werte (Passwörter) in Ansible Vault speichern.

Troubleshooting
---------------
- Operator nicht startend: `kubectl logs -n weblogic <operator-pod>`
- Domain CR nicht erkannt: sicherstellen, dass CRDs des Operators installiert sind (im Operator‑Manifest)
- PV/PVC Probleme: `kubectl describe pvc pvc-weblogic-home -n weblogic` und Node Pfad prüfen

Wichtige Hinweise zu SSH/InitScript
----------------------------------
- Das Init‑Script, das Hostkeys generiert und `/home/docker` anlegt, liegt als Datei `prepare_docker/gen-ssh-keys.sh` im Repo.
  Um die ConfigMap zu (re)generieren, nutze:

```bash
kubectl create configmap gen-ssh-keys-script --from-file=prepare_docker/gen-ssh-keys.sh -n weblogic --dry-run=client -o yaml > k8s/gen-ssh-keys-config.yaml
kc apply -f k8s/gen-ssh-keys-config.yaml
```

- Nach Änderung des Scripts musst du die betroffenen Deployments neu starten, damit InitContainers wiederlaufen:

```bash
kc rollout restart deployment/wls-admin -n weblogic
kc rollout restart deployment/wls-managed-1 -n weblogic
kc rollout restart deployment/wls-managed-2 -n weblogic
```

Hilfs‑Skripte
------------
- `prepare_docker/deploy-ssh-keys.sh` bereitet die Minikube Node‑Container vor (legt /home/docker an, kopiert `setup_user.sh` und deinen Public Key, bereitet hostPath PV Pfade vor).
- `prepare_docker/fix_wls_pods.sh` startet Rollouts, wartet auf Pods und verteilt (idempotent) den Public Key in die Pods falls nötig.

NodePort / SSH Zugriff
---------------------
- Für den schnellen Zugang aus dem Hostnetz sind NodePort Services definiert in `k8s/services-nodeports.yaml`.
  Diese öffnen die SSH‑Ports der Pods auf festen NodePorts (30222/30223/30224). Die `inventory.yaml` kann diese
  Node IP + NodePort Einträge verwenden, damit Ansible direkt per SSH verbindet.

Aufräumen / Aufteilung der Manifeste
-----------------------------------
- Die frühere monolithische Datei `k8s/ubuntu-wls-deployments.yaml` wurde archiviert als
  `k8s/ubuntu-wls-deployments.deprecated.yaml`. Nutze stattdessen die aufgeteilten Manifeste:
  `deploy-wls-admin.yaml`, `deploy-wls-managed-1.yaml`, `deploy-wls-managed-2.yaml`, `deploy-test-db.yaml`,
  sowie `services-clusterip.yaml` / `services-nodeports.yaml`.

