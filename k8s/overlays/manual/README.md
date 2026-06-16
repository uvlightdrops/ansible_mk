# Manual Overlay (ohne WebLogic Operator)

Dieses Overlay bildet den manuellen/legacy-nahen Weg ab:

- Namespace
- PV/PVC
- SSH-ConfigMaps
- Services (ClusterIP + NodePort)
- Admin + Managed Server Deployments
- Test-DB

## Anwenden über Ansible

```bash
cd /home/flow/dev_mk/ansible_mk
ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_manual.yml
```

## Direkter Kustomize-Check

```bash
cd /home/flow/dev_mk/ansible_mk
kubectl kustomize k8s/overlays/manual
```

## Hinweise

- Der Overlay verwendet aktuell `storageClassName: manual`.
- Die Workload-Manifeste referenzieren aktuell `wls-dev:1.3`.
- Für Hosted Cluster ohne NodePort/PV solltest du ein zusätzliches Overlay von `manual/` ableiten.

