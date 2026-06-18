# Manual Deploy ohne WebLogic Operator

Dieses Runbook ist fuer den Fall gedacht, dass der WebLogic Operator nicht genutzt werden kann.
Es deployt die Workloads direkt als Deployments/Services.

Die manuellen Pod-Deployments liegen unter `k8s/overlays/manual/` und enthalten
einen restriktiven `securityContext` (`runAsUser`, `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`).

## Kurz erklaert: Overlays und Kustomization

- `k8s/overlays/*` sind Umgebungsvarianten (`minikube`, `hosted`, `manual`).
- `kustomization.yaml` sagt, welche Ressourcen + Patches zusammen gebaut werden.
- Normalerweise nutzt man dafuer `kubectl apply -k <overlay>`.

## Warum bei euch `security` bei `kubectl apply -k` kommt

Eure `kustomization.yaml`-Dateien referenzieren Dateien mit `../../...` ausserhalb des Overlay-Ordners.
Der in `kubectl` integrierte Kustomize-Loader blockiert das standardmaessig.

Typischer Fehler:

```text
accumulating resources from '../../namespace.yaml': security; file is not in or below ...
```

## Empfohlener Weg: Deploy-Skript nutzen

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh
```

Hinweis: Standardmaessig werden `k8s/namespace.yaml` und `k8s/pv.yaml` dabei **nicht** angewendet.
Damit ist der Default fuer eingeschraenkte Cluster-RBAC geeignet.

Wenn dein User im Namespace keine PVC-Rechte hat (`kubectl auth can-i get/create pvc -n wl` = `no`),
kannst du den PVC-Schritt ebenfalls auslassen:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh --skip-pvc
```

Wenn du Namespace und PV explizit mit anlegen willst:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh --create-namespace --with-pv
```

Wenn der PVC danach `Pending` bleibt, setze explizit eine erlaubte StorageClass:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh --pvc-storage-class metro-nas
```

Hinweis: `--pvc-storage-class` setzt voraus, dass du den PVC patchen darfst.

Mit explizitem Cluster-Context:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh --kc-cmd "kubectl --context <dein-context>"
```

Vorschau ohne Aenderungen:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_no_operator.sh --dry-run
```

## Rollout Restart (Pods neu starten ohne Re-Apply)

Projekt-Skript (nutzt den bestehenden `prepare_docker`-Flow):

```bash
cd /home/flow/dev_mk/ansible_mk
prepare_docker/pd/restart_wls_rollouts.sh -n wl -k "kubectl --context <dein-context>"
```

Oder direkt mit `kubectl`:

```bash
kubectl rollout restart deployment/wls-admin -n wl
kubectl rollout restart statefulset/wls-managed-1 -n wl
kubectl rollout restart statefulset/wls-managed-2 -n wl
kubectl rollout restart statefulset/wls-managed-3 -n wl
```

Status beobachten:

```bash
kubectl rollout status deployment/wls-admin -n wl
kubectl rollout status statefulset/wls-managed-1 -n wl
kubectl rollout status statefulset/wls-managed-2 -n wl
kubectl rollout status statefulset/wls-managed-3 -n wl
```

## Undeploy (manueller Pfad)

Alle manuell deployten Ressourcen wieder entfernen:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/undeploy_manual_no_operator.sh --kc-cmd "kubectl --context <dein-context>"
```

Hinweis: Das Namespace-Objekt `wl` bleibt dabei standardmaessig erhalten.

Wenn du keine Rechte auf PV-Loeschung hast:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/undeploy_manual_no_operator.sh --skip-pv --kc-cmd "kubectl --context <dein-context>"
```

Wenn du das Namespace-Objekt explizit mit entfernen willst:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/undeploy_manual_no_operator.sh --delete-namespace --kc-cmd "kubectl --context <dein-context>"
```

Nur Vorschau:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/undeploy_manual_no_operator.sh --dry-run
```

## Alternative: direkte Manifeste anwenden

Arbeitsverzeichnis:

```bash
cd /home/flow/dev_mk/ansible_mk
```

Reihenfolge fuer den manuellen Start (ohne Operator):

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/pv.yaml
kubectl apply -f k8s/pvc-weblogic-home.yaml
kubectl apply -f k8s/gen-ssh-keys-config.yaml
kubectl apply -f k8s/weblogic-authorized-keys.yaml
kubectl apply -f k8s/services-clusterip.yaml
kubectl apply -f k8s/services-nodeports.yaml
kubectl apply -f k8s/deploy-test-db.yaml
kubectl apply -f k8s/overlays/manual/deploy-wls-admin.yaml
kubectl apply -f k8s/overlays/manual/deploy-wls-managed-1.yaml
kubectl apply -f k8s/overlays/manual/deploy-wls-managed-2.yaml
kubectl apply -f k8s/overlays/manual/deploy-wls-managed-3.yaml
```

Wenn der Namespace bereits existiert (z. B. per Rancher/Projektverwaltung), kannst du `k8s/namespace.yaml` weglassen.

## Status pruefen

```bash
kubectl get pods -n wl -o wide
kubectl get svc -n wl
kubectl get pvc -n wl
```

Live-Watch:

```bash
kubectl get pods -n wl -w
```

## Schnell-Diagnose bei Problemen

```bash
kubectl describe pod -n wl <pod-name>
kubectl logs -n wl <pod-name> --all-containers=true --tail=200
kubectl describe pvc -n wl pvc-weblogic-home
```

## Hinweis zu bestehenden Automationspfaden

- `group_vars/env_manual.yml` hat bereits `apply_operator: false`.
- Das Playbook `k8s_weblogic/deploy_weblogic.yml` nutzt aktuell trotzdem `kubectl apply -k` fuer das Overlay.
- Bei `security`-Fehlern daher dieses Runbook mit `kubectl apply -f ...` verwenden.

