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
- `k8s/pvc.yaml`         - PersistentVolumeClaim (Domain home)
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

Dev: schneller SSH‑Pod mit Java (nur für Tests)
---------------------------------------------
Wenn du per SSH in einen Pod testen willst, lege ich ein dev‑Image und ein Deployment an.

Build & load image in Minikube:
```bash
minikube -p wlcluster image build -t wls-dev:latest images/wls-dev
# alternativ: docker build -t wls-dev:latest images/wls-dev && minikube -p wlcluster image load wls-dev:latest
```

Deployment & Zugriff:
```bash
kubectl apply -f k8s/ssh-java-deploy.yaml -n weblogic
POD=$(kubectl get pods -n weblogic -l app=wls-dev -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n weblogic pod/$POD 2222:22 &
ssh -p 2222 weblogic@localhost
# Passwort in dev image: weblogic
```

Hinweis: Änderungen im Pod sind flüchtig. Nutze PVC/hostPath, wenn du persistente Daten brauchst.

