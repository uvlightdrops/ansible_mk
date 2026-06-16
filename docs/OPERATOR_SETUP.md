# WebLogic Operator Installation für Hosted Cluster

Die Domain-Definition benötigt einen laufenden **WebLogic Kubernetes Operator** im Cluster, um die Domain zu verwalten.

---

## Schritt 1: Operator-Status prüfen

```bash
# Gibt es schon CRDs?
kubectl api-resources | grep domain

# Ausgabe sollte einer der folgenden Werte sein:
#   domains                                          weblogic.oracle
#  oder
#   domains                                weblogic.oracle/v8
#
# Falls KEINE Ausgabe: Operator ist nicht installiert
```

Falls du die Ausgabe **nicht** siehst:

---

## Schritt 2: Kläre mit dem Plattform-Team

Frage deinen Cluster-Betreiber:

- **Q:** Ist der WebLogic Operator bereits cluster-weit installiert?
- **Expected:** Ja, CRDs sind verfügbar
- **Falls Nein:** Darf ich den Operator selbst installieren?

---

## Schritt 3: Operator selbst installieren (falls erlaubt)

### Option A: Empfohlener Weg für v4.3.9

Der alte Direkt-Link `.../releases/download/v4.3.9/weblogic-operator.yaml` existiert **nicht** mehr.
Für v4.3.9 installierst du den Operator heute über den **Helm-Chart** plus die beiden CRDs.

**CRDs für v4.3.9:**

```bash
kubectl apply -f https://raw.githubusercontent.com/oracle/weblogic-kubernetes-operator/v4.3.9/kubernetes/crd/domain-crd.yaml
kubectl apply -f https://raw.githubusercontent.com/oracle/weblogic-kubernetes-operator/v4.3.9/kubernetes/crd/cluster-crd.yaml
```

**Helm-Chart installieren:**

```bash
helm repo add weblogic-operator https://oracle.github.io/weblogic-kubernetes-operator/charts --force-update
helm repo update

# Namespace für den Operator
kubectl create namespace weblogic-operator

# Hosted-Cluster-freundliche Werte verwenden
helm install sample-weblogic-operator \
  weblogic-operator/weblogic-operator \
  --namespace weblogic-operator \
  --values k8s/operator-hosted-values.yaml \
  --wait
```

### Option B: Manifest lokal im Repo erzeugen

Wenn du weiterhin mit `kubectl apply -f k8s/operator.yaml` arbeiten willst, nutze:

```bash
./scripts/render_weblogic_operator_manifest.sh
kubectl apply -f k8s/operator.yaml
```

Der Generator kombiniert die CRDs und das vom Helm-Chart gerenderte Operator-Manifest in `k8s/operator.yaml`.

---

## Schritt 4: Operator-Pods prüfen

```bash
# Operator sollte in eigenem Namespace laufen:
kubectl get pods -n weblogic-operator
# oder (falls geändert):
kubectl get pods -n weblogic

# Output sollte so aussehen:
# NAME                               READY   STATUS    RESTARTS   AGE
# weblogic-operator-XXXXX           1/1     Running   0          2m

# Logs prüfen:
kubectl logs -n weblogic-operator -l app=weblogic-operator -f

# CRDs sollten verfügbar sein:
kubectl get crds | grep weblogic
```

---

## Schritt 5: Domain CR testen

Wenn der Operator läuft:

```bash
# Prüfe, ob Domain CRDs verfügbar:
kubectl api-resources | grep domain

# Das Playbook wird jetzt Domain CRs erstellen können:
kubectl get domains -n weblogic

# Nach dem Playbook sollte zunächst ein Fehler kommen (Image/CRDs-Check), das ist normal:
kubectl describe domain sample-domain1 -n weblogic
```

---

## Troubleshooting

### CRDs nicht verfügbar

```bash
# Problem: kubectl api-resources zeigt keine weblogic.oracle
# Lösung: Operator noch nicht installiert oder falsch

kubectl get crd
# Suche nach: domains.weblogic.oracle

# Falls nichts: Operator installieren mit den Schritten oben
```

### Operator Pods crashen

```bash
# Problem: weblogic-operator Pod ist in CrashLoopBackOff

kubectl logs -n weblogic-operator -l app=weblogic-operator

# Häufige Fehler:
# - ClusterRoleBinding fehlt: Frag dein Plattform-Team um RBAC
# - Namespace falsch: Prüfe mit kubectl get ns
# - Image Pull Error: Operator-Image in private Registry?
```

### Domain CR wird nicht erkannt

```bash
# Problem: kubectl get domains zeigt nichts

# Prüfe CRD-Definition:
kubectl describe crd domains.weblogic.oracle

# Prüfe Operator-Logs:
kubectl logs -n weblogic-operator deployment/weblogic-operator | grep -i domain

# Prüfe Domain-Manifest:
kubectl describe domain sample-domain1 -n weblogic
```

---

## Version-Kompatibilität

| WebLogic | Operator Version | Kubernetes |
|----------|-----------------|-----------|
| 14.1.1.0 | 4.3.x, 4.2.x    | 1.20+     |
| 12.2.1.4 | 3.3.x, 3.2.x    | 1.16+     |

Prüfe die offizielle Dokumentation: https://github.com/oracle/weblogic-kubernetes-operator

---

## Checkliste

- [ ] Operator-Status geklärt (zentral oder selbst installieren)
- [ ] CRDs vorhanden: `kubectl api-resources | grep domain`
- [ ] Operator Pod läuft (wenn selbst installiert): `kubectl get pods -n weblogic-operator`
- [ ] Operator-Logs OK: keine Error
- [ ] Bereit für Domain-Deployment

---

## Nächster Schritt

Mit funktionierendem Operator kannst du jetzt starten:

```bash
cd /home/flow/dev_mk/ansible_mk

# Pre-flight Check
bash scripts/preflight_check.sh weblogic

# Deployment
ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_hosted.yml
```

