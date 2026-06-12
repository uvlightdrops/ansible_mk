
## gemischte todos

1. logik der shell skripte im gesamtaufbau -  zb diverse checks als flags für ein skript - 
hier sieht man noch die fehler in der entstehungsgeschichte

## offene punkte shell konsolidierung

1. `pd.sh` weiter modularisieren (z. B. check/assemble/down in getrennte Source-Dateien), damit die Datei kleiner und review-freundlicher wird.
2. `check nodeport` robuster machen: Service/Pod-Zuordnung derzeit heuristisch; optional explizites Mapping ergänzen.
3. Config-Policy dokumentieren und leben: welche Variablen sind offiziell overridable (config.local.sh/env/CLI).
4. Parallele Python-CLI (`prepare_docker_py/`) klar als secondary markieren oder mittelfristig funktional angleichen/reduzieren.
5. Doku-Drift regelmäßig prüfen (z. B. monatlicher grep-Audit auf alte Begriffe/gelöschte Skripte).

