# Shell Architecture (prepare_docker)

Ziel: Eine klare, wartbare Shell-Struktur mit einem zentralen Einstiegspunkt und minimaler Duplikation.

## 1) Source of Truth

- Orchestrator: `prepare_docker/pd.sh`
- PD-Subskripte: `prepare_docker/pd/*.sh`
- Gemeinsame Helpers: `prepare_docker/common.sh`
- Diagnose-Helpers: `prepare_docker/diag_common.sh`
- Zentrale Defaults: `prepare_docker/config.defaults.sh`
- Lokale Overrides (optional): `prepare_docker/config.local.sh` (nicht versioniert)

## 2) Config Resolution Order

1. Harte Defaults in `config.defaults.sh`
2. Optionale lokale Overrides in `config.local.sh`
3. Environment-Variablen (z. B. `NAMESPACE`, `MK_PRF`, `KC_CMD`)
4. CLI-Argumente (`-n`, `-k`, command-spezifische Flags)

Hinweis: CLI gewinnt immer gegen env/defaults.

## 3) Argument Parsing

- Parser-API in `common.sh`: `parse_script_args <help_fn> <local_parser_fn> ...`
- Shared Flags: `-n`, `-k`, `-h`
- Lokale Flags pro Skript über Callback-Funktion
- Ziel: Keine verteilten ad-hoc `while/case` Parser in Einzelskripten

## 4) Command Responsibilities

- `pd.sh check`: gezielte Einzelchecks (`basic|home|ssh|nodeport`)
- `pd.sh diagnose`: Check-Kette; optional tiefe Artefakte mit `--full`
- `pd.sh assemble`: stufenweiser Aufbau (`--level pod|rollout|full`)
- `pd.sh down`: stufenweiser Rückbau (`--level ...`)
- Spezialskripte (z. B. `bootstrap_cluster.sh`, `recreate_storage.sh`) bleiben, nutzen aber gemeinsame Parser/Helpers.

## 5) What Should Not Reappear

- Keine neuen `loop_*.sh` Wrapper
- Keine pro-Skript Kopien von globalen Defaults (`NAMESPACE="weblogic"`, etc.)
- Keine direkten `$KC_CMD ...` Ketten, wenn `kc ...` verfügbar ist
- Keine doppelten Usage-Blöcke (Header + extra Text)

## 6) Quick Audit Commands

```bash
cd /home/flow/dev_mk/ansible_mk

grep -Rsn 'while \[ "\$#" -gt 0 \]\|getopts' prepare_docker/**/*.sh prepare_docker/*.sh

grep -Rsn '\$KC_CMD ' prepare_docker/**/*.sh prepare_docker/*.sh

grep -Rsn '\:-\$[A-Z0-9_]*_DEFAULT' prepare_docker/**/*.sh prepare_docker/*.sh
```

Erwartung:
- Parser-Schleifen hauptsächlich in `common.sh` (und ggf. bewusst in `pd.sh`-Subparsern)
- Keine direkten `$KC_CMD`-Reste
- `*_DEFAULT` Fallbacks zentral, nicht pro Funktionsskript

