# Environments: Minikube und gehostetes Kubernetes parallel pflegen

## Empfehlung in diesem Repo

Pflege **beide Umgebungen im selben Git-Branch**, aber trenne sie **im Verzeichnisbaum** über **Kustomize Overlays**:

- `k8s/base/` = portable, gemeinsame Manifeste
- `k8s/overlays/minikube/` = lokale Entwicklungsanpassungen
- `k8s/overlays/hosted/` = Anpassungen für das zentral gehostete Cluster
- `k8s/overlays/manual/` = manueller WebLogic-Weg ohne Operator (eigene Zielumgebung)

Wichtige Regel seit der Bereinigung:

- `k8s/deploy-wls-*.yaml` im Repo-Root sind **SSH-frei** (Kubernetes-only).
- SSH-bezogene Deployments liegen **nur** unter `k8s/overlays/minikube/`.

## Warum kein eigener Git-Branch pro Umgebung?

Ein Branch ist gut für:

- Feature-Arbeit
- Experimente
- Pull Requests

Ein Branch ist **nicht gut** als dauerhafte Trennung für Laufzeitumgebungen, weil dann sehr schnell Drift entsteht:

- Fixes müssen doppelt gemerged werden
- Reviews werden unübersichtlich
- Man verliert die gemeinsame Basis

Die Umgebung ist hier **keine alternative Historie**, sondern **eine Variante derselben Deployment-Artefakte**. Genau dafür sind Overlays gedacht.

## Was ist ein Overlay in diesem Kontext?

Ein Overlay ist eine kleine Schicht über gemeinsamen Kubernetes-Manifests.

Beispiel in diesem Repo:

- Das Basis-Manifest `k8s/domain.yaml` enthält die portable Domain-Definition.
- Das Overlay `k8s/overlays/minikube/` ergänzt Minikube-spezifische Dinge wie:
  - `hostPath`-PV
  - `NodePort`-Services
  - PVC `storageClassName: manual`
- Das Overlay `k8s/overlays/hosted/` lässt Cluster-Admin-nahe Dinge weg und setzt stattdessen nur eine Shared-Cluster-StorageClass.

## Aktuelle Aufteilung

### `k8s/base/`
Gemeinsam zwischen lokal und gehostet:

- `../pvc-weblogic-home.yaml`
- `../services-clusterip.yaml`
- `../domain.yaml`

### `k8s/overlays/minikube/`
Nur lokal:

- `../../namespace.yaml`
- `../../pv.yaml`
- `../../gen-ssh-keys-config.yaml`
- `../../weblogic-authorized-keys.yaml`
- `../../services-nodeports.yaml`
- `deploy-wls-admin.yaml`
- `deploy-wls-managed-{1,2,3}.yaml`
- Patch für PVC `storageClassName: manual`
- Patch für `spec.adminServer.nodePort: 30701`

Hinweis: Diese Deploy-Dateien enthalten InitContainer/SSH-Setup nur für Minikube-Dev.

### `k8s/overlays/hosted/`
Nur für das gehostete Cluster:

- kein `PersistentVolume` (`hostPath` entfällt)
- keine `NodePort`-Services
- Patch für PVC-StorageClass

### `k8s/overlays/manual/`
Manueller Weg ohne WebLogic Operator:

Diese Variante ist eine gleichwertige Umgebung
fuer Cluster, in denen der Operator nicht eingesetzt wird oder nicht eingesetzt werden kann.
Automation innerhalb der Pods erfolgt dabei ueber `kubectl exec` statt SSH.

- `../../namespace.yaml`
- `../../pv.yaml`
- `../../pvc-weblogic-home.yaml`
- `../../services-clusterip.yaml`
- `deploy-wls-admin.yaml`
- `deploy-wls-managed-{1,2,3}.yaml`
- `../../deploy-test-db.yaml`
- Patch für PVC `storageClassName: manual`

Hinweis: Diese Variante ist bewusst SSH-frei; Automation in Pods erfolgt per `kubectl exec`.

## Image-Profile (empfohlene Namenskonvention)

Zur klaren Trennung der Laufzeitprofile:

- Minikube mit SSH: `wls-dev-ssh:<tag>`
- Kubernetes ohne SSH (manual/hosted): `wls-dev-k8s:<tag>`

Beispiel:

- `harbor.example.com/team/wls-dev-ssh:1.3`
- `harbor.example.com/team/wls-dev-k8s:1.3`

So ist im Incident-Fall sofort sichtbar, welches Image fuer welches Overlay gedacht ist.

## Deployment über Ansible

Das Playbook `k8s_weblogic/deploy_weblogic.yml` ist jetzt overlay-fähig.

### Lokal / Minikube

```bash
cd /home/flow/dev_mk/ansible_mk
ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_minikube.yml
```

### Gehostetes Cluster

```bash
cd /home/flow/dev_mk/ansible_mk
ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_hosted.yml
```

### Manueller Weg (ohne Operator)

```bash
cd /home/flow/dev_mk/ansible_mk
ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_manual.yml
```

Alternative ohne Ansible (nur render + apply):

```bash
cd /home/flow/dev_mk/ansible_mk
RENDER_ONLY=true bash scripts/deploy_manual_no_operator.sh
# Output: ready2apply/manual-no-operator.rendered.yaml

# Wenn Rendering OK, dann anwenden:
bash scripts/deploy_manual_no_operator.sh
```

## Was du vor dem ersten Hosted-Deployment anpassen musst

In `group_vars/env_hosted.yml`:

- `namespace`
- optional `apply_operator`, falls der Operator doch von euch selbst verwaltet wird

In `k8s/overlays/hosted/patch-pvc-storageclass.yaml`:

- `REPLACE_WITH_SHARED_STORAGECLASS`

## Nächste sinnvolle Schritte

1. StorageClass des gehosteten Clusters eintragen
2. Namespace aus dem Plattform-Team übernehmen
3. Klären, ob der WebLogic Operator zentral betrieben wird
4. Danach optional ein drittes Overlay ergänzen, z. B. `k8s/overlays/staging/`
