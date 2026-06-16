# WebLogic Operator Installation für Hosted Clusters

## 📋 Übersicht

Das WebLogic Operator wurde in **zwei separate Dateien** aufgeteilt, weil es zwei verschiedene Berechtigungsebenen braucht:

| Datei | Berechtigungen | Wer installiert |
|-------|---|---|
| `operator-crds-cluster-admin.yaml` | **Cluster-Admin** | Dein Plattform-Team |
| `operator-namespace.yaml` | **Namespace-User** | Du (in deiner Namespace) |

---

## 🔧 **Schritt 1: Cluster-Admins installieren die CRDs**

**Das macht der Cluster-Admin einmalig pro Cluster:**

```bash
# Nur die CRDs installieren (braucht Cluster-Admin-Rechte)
kubectl apply -f k8s/operator-crds-cluster-admin.yaml

# Überprüfen:
kubectl get crd domains.weblogic.oracle
kubectl get crd clusters.weblogic.oracle
```

**Was wird dabei installiert:**
- `CustomResourceDefinition domains.weblogic.oracle`
- `CustomResourceDefinition clusters.weblogic.oracle`

→ **Diese CRDs sind cluster-wide und betreffen ALLE Namespaces!**

---

## ⚡ **Schritt 2: Du installierst den Operator in deiner Namespace**

**Das machst du nach der CRD-Installation:**

```bash
# Namespace erstellen
kubectl create namespace weblogic-operator

# Operator installieren (braucht NUR Namespace-Rechte)
kubectl apply -f k8s/operator-namespace.yaml

# Überprüfen:
kubectl get deployment -n weblogic-operator
kubectl get pods -n weblogic-operator
kubectl logs -n weblogic-operator -l app=weblogic-operator
```

**Was wird dabei installiert:**
- Secret `weblogic-operator-secrets` (leer, für später)
- ConfigMap `weblogic-operator-cm` (Operator-Konfiguration)
- 4x Roles (RBAC-Berechtigungen in deiner Namespace)
- 3x RoleBindings (Bindet Roles an Service-Account)
- Deployment `weblogic-operator` (der eigentliche Operator-Pod)

---

## ✅ **Sicherheitsmodell**

```
┌─────────────────────────────────────────┐
│      Cluster-Level (Cluster-Admin)      │
│  ├─ domains.weblogic.oracle CRD         │
│  └─ clusters.weblogic.oracle CRD        │
└─────────────────────────────────────────┘
                 ↓
        (Alle Namespaces können
         diese Ressourcentypen nutzen)
                 ↓
┌─────────────────────────────────────────┐
│   Namespace: weblogic-operator          │
│  ├─ Operator Deployment (überwacht)     │
│  ├─ Roles (nur diese Namespace)         │
│  └─ RoleBindings (nur diese Namespace)  │
└─────────────────────────────────────────┘
```

**Wichtig:** 
- Der Operator hat nur Rechte **in seiner Namespace**
- Er kann andere Namespaces **NICHT** beeinflussen
- Mehrere Namespaces können Domain-Ressourcen definieren, wenn sie wollen

---

## 📋 **Checkliste**

- [ ] Cluster-Admin hat `operator-crds-cluster-admin.yaml` angewendet
- [ ] CRDs sind sichtbar: `kubectl get crd domains.weblogic.oracle`
- [ ] Namespace `weblogic-operator` existiert
- [ ] `kubectl apply -f operator-namespace.yaml` erfolgreich
- [ ] Operator-Pod läuft: `kubectl get pods -n weblogic-operator`

---

## 🚀 **Nächste Schritte**

Nach erfolgreicher Installation kannst du:

```bash
# Domain-Ressourcen erstellen
kubectl apply -f k8s/domain.yaml

# Operator übernimmt jetzt automatisch:
# - Domain-Initialisierung
# - Pod-Erstellung
# - Fehlerbehandlung
# - Health-Checks
```

---

## ⚠️ **Troubleshooting**

**Problem:** `error: unable to recognize "operator-namespace.yaml": no matches for kind "Domain"...`

**Lösung:** CRDs sind noch nicht installiert. Frag die Cluster-Admins, `operator-crds-cluster-admin.yaml` zu installieren.

```bash
# CRDs überprüfen:
kubectl get crd | grep weblogic
```

**Problem:** Pod startet nicht, RBAC-Fehler

**Lösung:** Überprüfen, dass dein Service-Account die Roles hat:

```bash
kubectl auth can-i list domains --as=system:serviceaccount:weblogic-operator:default
```

---

## 📚 **Dateien**

- `operator-crds-cluster-admin.yaml` (1,3 MB)
  - Domain CRD (23,372 Zeilen)
  - Cluster CRD (3,328 Zeilen)

- `operator-namespace.yaml` (12 KB)
  - Secret, ConfigMap, Roles, RoleBindings, Deployment (360 Zeilen)

- Generiert mit: `scripts/render_weblogic_operator_manifest.sh v4.3.9`

