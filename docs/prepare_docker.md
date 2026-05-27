# prepare_docker — Hilfs‑Skripte für Minikube / Dev Cluster

Dieses Dokument listet und erklärt die kleinen Shell‑Skripte im Verzeichnis `prepare_docker/`.
Die Skripte dienen zur lokalen Vorbereitung von Minikube‑Node‑Containern, Erzeugung der ConfigMap
für das Init‑Script, sowie zur einfachen Verteilung des Public SSH‑Keys in Test‑Pods.

Pfad: `prepare_docker/`

Wichtige Skripte
- `collect_minikube_diagnostics.sh` — Diagnose‑Skript, sammelt `minikube`/`kubectl`/`docker` Informationen
  und schreibt sie in `out.diagnostics/` (nützlich zur Fehlersuche bei NotReady‑Nodes und Pods).
- `deploy-ssh-keys.sh` — bereitet die Minikube Node‑Container vor:
  - legt `/home/docker/.ssh` an
  - kopiert `setup_user.sh` und das angegebene Public Key in den Node‑Container
  - führt `setup_user.sh` im Node aus (idempotent erzeugt den Benutzer `docker`, sudoers, `.ssh/authorized_keys`)
  - optional: bereitet hostPath PV Pfade vor und setzt Ownership (UID 1000)

- `setup_user.sh` — idempotentes Script, das in einem Node‑Container ausgeführt wird und:
  - den Benutzer `docker` anlegt (falls noch nicht vorhanden),
  - eine sudoers‑Datei für ihn erstellt (0440),
  - `~/.ssh/authorized_keys` anlegt und den übergebenen Public Key hinzufügt,
  - die korrekten Rechte (700/600) setzt.

- `gen-ssh-keys.sh` — Init‑Container Script (ausführbar), erzeugt SSH Hostkeys, legt eine minimal
  `sshd_config` an und sorgt dafür, dass `/home/docker/.ssh/authorized_keys` vorhanden ist. Dieses Script
  wird in einer ConfigMap bereitgestellt und in Deployments als InitContainer ausgeführt.

- `fix_wls_pods.sh` — Convenience‑Script (repo) das:
  - Rollouts der WLS‑Deployments anstößt (damit InitContainers laufen),
  - wartet auf Pods und versucht anschließend idempotent den Public Key in alle Pods zu schreiben.

- `mk_start.sh` — lokale Start‑Hilfen für Minikube (projektspezifische Alias/Startbefehle).

Neu hinzugefügte helper‑Skripte (repo)
- `loop_install_pubkey.sh` — iteriert über alle Pods im Namespace und fügt den Public Key idempotent in
  `/home/docker/.ssh/authorized_keys` ein (nur wenn `/home/docker` existiert). Usage: `./loop_install_pubkey.sh -n weblogic -p ~/.ssh/id_ed25519_docker.pub`.
- `loop_check_home.sh` — listet `/home` und `/home/docker/.ssh` für alle Pods und zeigt Rechte an.
- `restart_wls_rollouts.sh` — startet Rollouts für `wls-admin`, `wls-managed-1`, `wls-managed-2`, `wls-dev` und wartet auf Status.
- `gen_configmap_from_script.sh` — generiert `k8s/gen-ssh-keys-config.yaml` aus `prepare_docker/gen-ssh-keys.sh` und wendet die ConfigMap an.

Ordner mit Ausgaben
- `out.diagnostics/` — Ergebnisse von `collect_minikube_diagnostics.sh`.
- `out.mk/` — zusätzliche projektspezifische Outputs (z. B. minikube diagnostics cached).

Tipps
- Bei Problemen mit InitContainers (z. B. Permission denied) prüfe zuerst die ConfigMap‑Mountrechte
  (`defaultMode`) und die InitContainer‑Logs (`kubectl logs -c gen-ssh-keys --previous`).
- Falls `ssh-keygen` im Image fehlt, entweder das Image anpassen oder für InitContainer ein anderes Image
  (z. B. `ubuntu:22.04`) zum Generieren der Hostkeys verwenden.

Beispiel‑Workflow (schnell)
1. Erzeuge/aktualisiere die ConfigMap:
   ```bash
   ./prepare_docker/gen_configmap_from_script.sh -n weblogic
   ```
2. Rollout restart:
   ```bash
   ./prepare_docker/restart_wls_rollouts.sh -n weblogic
   ```
3. Key in Pods verteilen (falls InitContainer nur Home anlegt):
   ```bash
   ./prepare_docker/loop_install_pubkey.sh -n weblogic -p ~/.ssh/id_ed25519_docker.pub
   ```

