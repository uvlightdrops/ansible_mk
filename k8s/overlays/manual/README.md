# Manual Overlay (ohne WebLogic Operator)

Dieser Pfad deployt klassische Deployments/Services direkt, ohne Domain-CR und ohne Operator.

## Kurz: Overlay und Kustomization

- `k8s/overlays/*` sind Umgebungsvarianten (minikube/hosted/manual).
- `kustomization.yaml` ist die Zusammensetzung: welche Ressourcen + welche Patches gelten.
- Build/Apply ist normalerweise: `kubectl apply -k <overlay-dir>`.

## Warum bei `apply -k` ein `security`-Fehler kommt

In diesem Repo referenziert das Overlay Dateien per `../../...` (z. B. `../../namespace.yaml`).
Der in `kubectl` eingebaute Kustomize-Loader blockiert standardmaessig Dateien ausserhalb des Overlay-Verzeichnisses.

Typischer Fehler:

```text
accumulating resources from '../../namespace.yaml': security; file is not in or below ...
```

## Manueller Deploy ohne Kustomize (empfohlen fuer jetzt)

```bash
cd /home/flow/dev_mk/ansible_mk
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/pv.yaml
kubectl apply -f k8s/pvc-weblogic-home.yaml
kubectl apply -f k8s/gen-ssh-keys-config.yaml
kubectl apply -f k8s/weblogic-authorized-keys.yaml
kubectl apply -f k8s/services-clusterip.yaml
kubectl apply -f k8s/services-nodeports.yaml
kubectl apply -f k8s/deploy-test-db.yaml
kubectl apply -f k8s/deploy-wls-admin.yaml
kubectl apply -f k8s/deploy-wls-managed-1.yaml
kubectl apply -f k8s/deploy-wls-managed-2.yaml
kubectl apply -f k8s/deploy-wls-managed-3.yaml
```

```bash
kubectl get pods -n weblogic -w
```

## Optional ueber Ansible

`group_vars/env_manual.yml` setzt zwar `apply_operator: false`, nutzt aber intern derzeit `kubectl apply -k`.
Bei dem oben genannten Loader-Fehler daher aktuell besser den manuellen `kubectl apply -f ...`-Pfad nutzen.

## Hinweise

- `storageClassName` fuer den Manual-Pfad wird ueber die PVC-Manifestdatei bestimmt.
- Workloads referenzieren im Repo-Stand typischerweise `wls-dev:1.3`.

