# prepare_docker — Hilfs‑Skripte für Minikube / Dev Cluster

## Neu strukturierter Einstieg: `prepare_docker/pd.sh`

Um die historisch gewachsenen Einzel-Skripte konsistenter zu bedienen, gibt es jetzt einen zentralen Shell-Entry-Point:

```bash
./prepare_docker/pd.sh [global options] <command> [command options]
```

Logische Gliederung (Aspekte)
- Targeting:
  - default: einzelnes Ziel (`--pod <name>` oder `--label ...`)
  - `-a` / `--all`: auf alle Pods loopen
  - optional `--label app=...` fuer gefilterte Pod-Auswahl
- Ausgabe/Logging:
  - `-v` fuer mehr Details
  - `--quiet` fuer reduzierte Konsolenausgabe
  - `--log-file <path>` fuer persistentes Command/Output Logging
  - `--dry-run` fuer planbare, nicht-ausgefuehrte Runs

Zentrale Konfiguration (Defaults)
- Gemeinsame Standardwerte liegen in `prepare_docker/config.defaults.sh` (z. B. `NAMESPACE_DEFAULT`, `MK_PRF_DEFAULT`, `PV_PATH_DEFAULT`, `AUTO_YES_DEFAULT`).
- Optional kannst du lokale Overrides in `prepare_docker/config.local.sh` hinterlegen.
- Alle Scripts laden diese Defaults ueber `prepare_docker/common.sh`; CLI-Argumente haben weiterhin Vorrang.

Logische Bereiche (Commands)
- `check`: einzelner Check, z. B. `check basic|home|ssh|nodeport`
- `diagnose`: fuehrt alle Checks hintereinander aus (optional `--full`)
- `assemble`: System schrittweise aufbauen
- `down`: System schrittweise herunterfahren

Analoge `--level` Logik
- `assemble --level pod|rollout|full`
- `down --level scale-down|soft|resources|namespace|all`

Convenience-Wrapper
- `up`: `assemble` + `diagnose`
- `doctor`: `diagnose --full --crashloops`

Beispiele

```bash
./prepare_docker/pd.sh --pod wls-managed-1-0 check ssh
./prepare_docker/pd.sh --pod wls-admin-0 check home
./prepare_docker/pd.sh -a diagnose
./prepare_docker/pd.sh -a diagnose --full --crashloops
./prepare_docker/pd.sh -a assemble --level full
./prepare_docker/pd.sh --log-file prepare_docker/out.diagnostics/pd.log assemble --level pod
./prepare_docker/pd.sh -a doctor
./prepare_docker/pd.sh down --level scale-down -y
```

Hinweis zur Konsolidierung
- `pd.sh` ist der zentrale Shell-Entry-Point; fruehere `loop_*` Varianten sind entfernt.

Dieses Dokument listet und erklärt die kleinen Shell‑Skripte im Verzeichnis `prepare_docker/`.
Die Skripte dienen zur lokalen Vorbereitung von Minikube‑Node‑Containern, Erzeugung der ConfigMap
für das Init‑Script, sowie zur einfachen Verteilung des Public SSH‑Keys in Test‑Pods.

Pfad: `prepare_docker/`

Wichtige Skripte
- `collect_minikube_diagnostics.sh` — Diagnose‑Skript, sammelt `minikube`/`kubectl`/`docker` Informationen
  und schreibt sie in `out.diagnostics/` (nützlich zur Fehlersuche bei NotReady‑Nodes und Pods).
- `pd/deploy-ssh-keys.sh` — bereitet die Minikube Node‑Container vor:
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

Skripte mit eigenem Aufruf (intern auch in `pd.sh` verwendet)
- `pd/restart_wls_rollouts.sh` — startet Rollouts für `wls-admin`, `wls-managed-1`, `wls-managed-2`, `wls-dev` und wartet auf Status.
- `pd/gen_configmap_from_script.sh` — generiert `k8s/gen-ssh-keys-config.yaml` aus `prepare_docker/gen-ssh-keys.sh` und wendet die ConfigMap an.


 - `reap_terminating.sh` — versucht Pods im `Terminating` Zustand aufzuräumen: normales Löschen, kurz warten,
   bei Bedarf Finalizer entfernen und force-delete. Usage: `./reap_terminating.sh -n weblogic`.
Ordner mit Ausgaben
- `out.diagnostics/` — Ergebnisse von `collect_minikube_diagnostics.sh`.
- `out.mk/` — zusätzliche projektspezifische Outputs (z. B. minikube diagnostics cached).

Tipps
- Bei Problemen mit InitContainers (z. B. Permission denied) prüfe zuerst die ConfigMap‑Mountrechte
  (`defaultMode`) und die InitContainer‑Logs (`kubectl logs -c gen-ssh-keys --previous`).
- Falls `ssh-keygen` im Image fehlt, entweder das Image anpassen oder für InitContainer ein anderes Image
  (z. B. `ubuntu:22.04`) zum Generieren der Hostkeys verwenden.

Beispiel‑Workflow (schnell) — via `pd.sh`
1. Erzeuge/aktualisiere die ConfigMap + Rollouts + Pubkeys:
   ```bash
   ./prepare_docker/pd.sh -a assemble --level rollout
   ```
2. Pubkeys nur in Pods verteilen (ohne Rollout):
   ```bash
   ./prepare_docker/pd.sh -a assemble --level pod
   ```
3. Alles prüfen (Home + SSH + NodePort):
   ```bash
   ./prepare_docker/pd.sh -a diagnose
   ```

      ## Ablauf: `build_and_deploy_wls_dev.sh` und `gen-ssh-keys.sh`

      Kurz und knapp:

      - `prepare_docker/build_and_deploy_wls_dev.sh`: baut das Dev‑Image lokal, lädt es in Minikube und startet die WLS‑Deployments neu.
      - `prepare_docker/gen-ssh-keys.sh`: Init‑Script (InitContainer) im Pod — erzeugt Host‑Keys, stellt `/home/docker/.ssh/authorized_keys` sicher, liest Pubkeys aus `/pubkeys` ein und setzt best‑effort Owner/Perms.

      Details — `build_and_deploy_wls_dev.sh`:
      1. `docker build -t $IMAGE_TAG images/wls-dev` (lokal)
      2. `minikube image load $IMAGE_TAG` (lädt Image in Minikube)
      3. `kc rollout restart deployment/... -n $NAMESPACE` (neustartet Deployments)
      4. `kc get pods -n $NAMESPACE -o wide` (zeigt Pods)

      Details — `gen-ssh-keys.sh` (InitContainer):
      1. Restore `/etc/ssh` aus `/etc/ssh.orig` falls vorhanden.
      2. `ssh-keygen -A` — erzeugt fehlende Host‑Keys (wichtig bei emptyDir für `/etc/ssh`).
      3. `mkdir -p /home/docker/.ssh` und `touch /home/docker/.ssh/authorized_keys`.
      4. Für alle `*.pub` in `/pubkeys`: prüfe ob bereits vorhanden, sonst append (idempotent).
      5. Best‑effort `chown` auf `docker` (oder fallback 1000:1000) und chmod 700/600.

      Kurzbefehle zur Diagnose:
      ```bash
      # Build + load + restart
      ./prepare_docker/build_and_deploy_wls_dev.sh

      # Apply ConfigMap with pubkeys
      kc apply -f k8s/weblogic-authorized-keys.yaml

      # Check InitContainer logs and authorized_keys
      POD=$(kc get pods -n weblogic -l app=wls-admin -o jsonpath='{.items[0].metadata.name}')
      kc logs -n weblogic $POD -c gen-ssh-keys --tail=200
      kc exec -n weblogic $POD -c wls-admin -- sh -c 'ls -ln /home/docker /home/docker/.ssh /home/docker/.ssh/authorized_keys || true; sed -n "1,20p" /home/docker/.ssh/authorized_keys || true'

      # Temporary perms fix (debug as root)
      kc debug -n weblogic pod/$POD -it --image=alpine --target=wls-admin -- sh -c "chown -R docker:docker /home/docker || true; chmod 700 /home/docker/.ssh || true; chmod 600 /home/docker/.ssh/authorized_keys || true"
      ```

Vorbereitung der lokalen Umgebung
---------------------------------
Kurz und knapp (für Fortgeschrittene): damit die Skripte reproduzierbar in non‑interactive Shells laufen, lege ich einen kleinen `kc`‑Wrapper ins Repo (`tools/kc`).
Er macht exakt das, was dein interaktives Alias tut: `minikube -p $MK_PRF kubectl -- -n $WL_NS`, und ist script‑freundlich.

Schnelle Schritte:

```bash
# 1) ausführbar machen (einmalig)
chmod +x tools/kc prepare_docker/*.sh

# 2) tools ins PATH (temporär für diese Shell)
export PATH="$(pwd)/tools:$PATH"

# 3) Test: kc ohne Namespace injectet default namespace
kc get pods            # -> minikube -p wlcluster kubectl -- -n weblogic get pods
kc get pods -n kube-system  # respects explicit namespace
```

Konfiguration:
- `MK_PRF` (default `wlcluster`): Minikube‑Profile, das `tools/kc` verwendet.
- `WL_NS` (default `weblogic`): Default‑Namespace, das in Skripten injiziert wird, wenn kein `-n` angegeben ist.

Empfehlung fürs User‑Shell‑Setup (`~/.bashrc`):

```bash
# Add project tools to PATH (project-local wrapper)
export PATH="$HOME/dev_mk/ansible_mk/tools:$PATH"

# Optionally override defaults
export MK_PRF=wlcluster
export WL_NS=weblogic
```

Warum das so gemacht ist: Aliasse in `~/.bashrc` sind für interaktive Shells; scripts laufen meist in non‑interactive shells
und sehen keine aliases. Ein kleines ausführbares `kc` ist reproduzierbar, CI‑freundlich und vermeidet `eval` oder `source ~/.bashrc` in Skripten.

Python CLI
----------

Es gibt eine kleine Python‑Toolchain unter `prepare_docker_py/` mit einem CLI‑Entrypoint.

- `tools/pd` ist der **primaere Shell-Entry-Point** (delegiert auf `prepare_docker/pd.sh`).
- `tools/pd-secondary` startet die Python-CLI und ist bewusst als **secondary** benannt.

Beispiel:
```bash
chmod +x tools/pd tools/pd-secondary

# primary (shell)
tools/pd -a diagnose

# secondary (python)
tools/pd-secondary get-pod -n weblogic
tools/pd-secondary loop-install-pubkey -n weblogic -k ~/.ssh/id_ed25519_docker
```



## Dateien im Detail: `k8s/gen-ssh-keys-config.yaml` und `prepare_docker/gen-ssh-keys.sh`

Diese beiden Dateien sind zentral für das Einrichten von SSH‑Zugriff in den Dev‑Pods. Kurz:

- `prepare_docker/gen-ssh-keys.sh` ist das Init/Bootstrap‑Script, das im Pod ausgeführt wird.
  - Es erzeugt SSH‑Hostkeys (ssh-keygen -A), erstellt/prüft `/home/docker/.ssh/authorized_keys` und liest
    Public‑Keys aus `/pubkeys` (ConfigMap) ein. Die Installation ist idempotent (prüft vorher per grep).
  - Setzt best‑effort Ownership/Perms (chown auf `docker` oder fallback 1000:1000, chmod 700/600).
  - Wird bewusst robust geschrieben (Fehler werden toleriert) und enthält Debug‑Ausgaben.

- `k8s/gen-ssh-keys-config.yaml` ist eine ConfigMap, die das Script als Datei (`gen-ssh-keys.sh`) enthält.
  - In Deployments wird diese ConfigMap als Volume gemountet (z. B. `/scripts`) und die Datei als InitContainer ausgeführt.
  - WICHTIG: setze `defaultMode: 0755` beim ConfigMap‑Volume, sonst ist die Datei nicht ausführbar und InitContainer schlägt fehl.

Wie sie zusammenarbeiten
- Erzeuge/aktualisiere die ConfigMap aus dem lokalen Script (siehe `gen_configmap_from_script.sh`).
- Apply der ConfigMap sorgt dafür, dass alle Pods beim nächsten Start das aktuelle Script verwenden.
- Der InitContainer führt das Script (als root) aus — dadurch können Host‑Keys generiert und `/home/docker` korrekt vorbereitet werden.

Kurzbefehle (kopierbar):
```bash
# Erzeuge/aktualisiere die ConfigMap aus dem lokalen Script
./prepare_docker/pd/gen_configmap_from_script.sh -n weblogic

# Wende die ConfigMap an
kc apply -f k8s/gen-ssh-keys-config.yaml

# Starte die Deployments neu, damit InitContainers laufen
./prepare_docker/pd/restart_wls_rollouts.sh -n weblogic

# Prüfe InitContainer Logs
POD=$(kc get pods -n weblogic -l app=wls-admin -o jsonpath='{.items[0].metadata.name}')
kc logs -n weblogic $POD -c gen-ssh-keys --tail=200
```
 
Erweiterte Diagnose (komplexere Befehle)
--------------------------------------

Wenn ein Rollout hängt oder ein Pod im CrashLoop/BackOff ist, helfen die folgenden Befehle, die Ursache systematisch zu finden und zu reparieren. Führe die Befehle nacheinander aus und lese die Ausgaben aufmerksam.

1) Pods / Übersicht
```bash
kc get pods -n weblogic -o wide
```

2) Detaillierte Pod‑Beschreibung (Events)
```bash
kc describe pod -n weblogic $POD
```

3) Aktuelle Events (letzte 40)
```bash
kc get events -n weblogic --sort-by=.lastTimestamp | tail -n 40
```

4) InitContainer‑Logs (gen-ssh-keys)
```bash
kc logs -n weblogic $POD -c gen-ssh-keys --tail=300
```

5) Main container Logs (falls vorhanden / vorherige Instanz)
```bash
kc logs -n weblogic $POD -c wls-admin --tail=300
kc logs -n weblogic $POD -c wls-admin --previous --tail=300 || true
```

6) Prüfe geteilte Volumes in Pod (mounts/volumes)
```bash
kc get pod -n weblogic $POD -o yaml | sed -n '1,240p' | sed -n '/volumeMounts:/,/env:/p'
kc get pod -n weblogic $POD -o yaml | sed -n '1,240p' | sed -n '/volumes:/,/status:/p'
```

7) Untersuche Inhalt der geteilten Volumes mit einem Ephemeral/Debug Container
```bash
kc debug -n weblogic pod/$POD -it --image=alpine -- sh -c 'ls -la /etc/ssh || true; stat -c "%n %U:%G %a" /etc/ssh/ssh_host_* 2>/dev/null || true; ls -la /home/docker/.ssh || true; sed -n "1,40p" /home/docker/.ssh/authorized_keys || true'
```

8) Erzeuge einmalig Host‑Keys im shared volume (falls fehlen)
```bash
kc debug -n weblogic pod/$POD -it --image=alpine -- sh -c 'apk add --no-cache openssh >/dev/null 2>&1 || true; ssh-keygen -A || true; ls -la /etc/ssh; stat -c "%n %U:%G %a" /etc/ssh/ssh_host_*'
```

### Aufräumen: Pods im "Terminating" Zustand

Wenn Pods nicht verschwinden (z.B. `kubectl get pods` zeigt `Terminating` bzw. `deletionTimestamp` gesetzt), hilft das Script `prepare_docker/reap_terminating.sh`.

Kurzfunktionalität:
- versucht zuerst ein normales `kubectl delete pod`;
- wartet (default 10s);
- wenn Pod noch vorhanden, versucht `patch` um Finalizer zu entfernen und macht ein force-delete.

Beispiel:
```bash
./prepare_docker/reap_terminating.sh -n weblogic
```

Warnung: force-delete kann zu inkonsistentem Zustand bei Stateful Volumes führen — nutze nur wenn normaler Delete fehlschlägt.

## Neues: strukturierte Diagnostics Sammlung

Ein neues Script `prepare_docker/pd/collect_diagnostics.sh` sammelt cluster- und namespace‑weit
Diagnosedaten und schreibt sie in ein timestamped Verzeichnis unter `out.diagnostics/`.

Kurz: es erzeugt `out.diagnostics/<YYYYMMDDTHHMMSSZ>/` mit Unterverzeichnissen pro Namespace
(`ns-<name>`) und je Pod ein Verzeichnis mit `describe.txt`, `pod.yaml` und `log.*.txt` Dateien.

Usage (einfach):
```bash
# Namespace-spezifisch
./prepare_docker/pd/collect_diagnostics.sh -n weblogic

# Alle Namespaces (länger)
./prepare_docker/pd/collect_diagnostics.sh -a

# Optional: nach Sammeln Reap ausführen (versucht Terminating Pods aufzuräumen)
./prepare_docker/pd/collect_diagnostics.sh -n weblogic --reap
```

Ergebnis: Ein Archivierbares `out.diagnostics/<ts>/` mit allen relevanten Outputs, das du
z.B. an Kollegen oder in ein Issue anhängen kannst.

CrashLoop‑Diagnose
------------------

Ein neues spezialisiertes Script `prepare_docker/pd/diagnose_crashloops.sh` sammelt gezielt
Informationen für Pods im `CrashLoopBackOff` Zustand. Es legt pro Pod ein Verzeichnis
an mit `describe.txt`, `pod.yaml`, `node.describe.txt`, `log.<container>.txt`,
`log.<container>.previous.txt` und `events.txt`.

Usage (kurz):
```bash
# Namespace-spezifisch
./prepare_docker/pd/diagnose_crashloops.sh -n weblogic

# Alle Namespaces
./prepare_docker/pd/diagnose_crashloops.sh -a

# Anpassen: tail lines und output dir
./prepare_docker/pd/diagnose_crashloops.sh -n weblogic -t 200 -o out.diagnostics/custom
```

Die Ausgabe landet unter `out.diagnostics/<timestamp>/crashloops/` (oder deinem `-o` Ziel).



9) Korrigiere Rechte best‑effort (falls Host‑Keys vorhanden, aber falsche Owner/Perms)
```bash
kc debug -n weblogic pod/$POD -it --image=alpine -- sh -c 'chown root:root /etc/ssh/ssh_host_* 2>/dev/null || true; chmod 600 /etc/ssh/ssh_host_* 2>/dev/null || true; chown -R docker:docker /home/docker || true; chmod 700 /home/docker/.ssh || true; chmod 600 /home/docker/.ssh/authorized_keys || true'
```

Diagnose‑Beispiele (gemeldet vom Operator)
-----------------------------------------
Die folgenden Ausgaben wurden während der Fehlersuche berichtet — sie sind beispielhafte Hinweise, was typischerweise schief läuft:

- Pod BackOff / kubelet Warning (zeigt, dass der Hauptcontainer wiederholt crasht):

  Warning  BackOff    2m22s (x41 over 42m)  kubelet            spec.containers{wls-admin}: Back-off restarting failed container wls-admin in pod wls-admin-84f7955bfc-n5c9l_weblogic(...)

- InitContainer lief durch (Ende‑Marker):

  === gen-ssh-keys END ===
  Tue Jun  2 12:14:36 UTC 2026

- Main container Log: sshd bricht ab wegen fehlender Host‑Keys:

  sshd: no hostkeys available -- exiting.

Und ein früherer Hinweis auf Permission‑Probleme beim Lesen der authorized_keys:

  sed: can't read /home/docker/.ssh/authorized_keys: Permission denied

Diese Meldungen deuten auf ein Problem mit dem geteilten `/etc/ssh` Volume oder mit Owner/Perms 
des Home‑Verzeichnisses hin — die obigen Debug‑Befehle (Ephemeral Container + ssh-keygen) helfen, 
den Zustand zu reparieren.




