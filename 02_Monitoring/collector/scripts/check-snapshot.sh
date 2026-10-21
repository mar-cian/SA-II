#!/usr/bin/env bash
# Prueft den zuletzt geschriebenen Snapshot und gibt ihn lesbar aus.
# Dient als Beleg fuer das Testprotokoll und als Gegenprobe zum Dashboard.
#
# Aufruf:
#   ./scripts/check-snapshot.sh
#   ./scripts/check-snapshot.sh /var/lib/hf-ops-collector/state/snapshot.json
#   ./scripts/check-snapshot.sh --logs        zusaetzlich die letzten Logzeilen
#
# Exit-Codes
#   0 Snapshot frisch, Datenerfassung ok
#   1 Snapshot frisch, aber Datenerfassung degradiert
#   2 Snapshot veraltet (Alter groesser als max_age_seconds)
#   3 Snapshot fehlt, ist leer oder kein gueltiges JSON
set -uo pipefail

SHOW_LOGS=0
SNAPSHOT=""
for arg in "$@"; do
  case "$arg" in
    --logs) SHOW_LOGS=1 ;;
    *)      SNAPSHOT="$arg" ;;
  esac
done
if [ -z "${SNAPSHOT}" ]; then
  SNAPSHOT="${HFC_OUT_DIR:-/var/lib/hf-ops-collector/state}/${HFC_OUT_FILE:-snapshot.json}"
fi

if [ ! -s "${SNAPSHOT}" ]; then
  printf 'UNKNOWN: Snapshot %s fehlt oder ist leer.\n' "${SNAPSHOT}" >&2
  printf 'Collector-Status pruefen: sudo systemctl status hf-ops-collector\n' >&2
  printf 'Keine Daten bedeutet nicht "alles gesund".\n' >&2
  exit 3
fi

SHOW_LOGS="${SHOW_LOGS}" python3 - "${SNAPSHOT}" <<'PY'
import json, os, sys
from datetime import datetime, timezone

path = sys.argv[1]
show_logs = os.environ.get("SHOW_LOGS") == "1"
try:
    with open(path, encoding="utf-8") as handle:
        snap = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    print(f"UNKNOWN: {path} nicht lesbar oder kein gueltiges JSON: {exc}", file=sys.stderr)
    sys.exit(3)

coll = snap.get("collector", {})
max_age = coll.get("max_age_seconds", 20)
measured = coll.get("measured_at_epoch")
age = round(datetime.now(timezone.utc).timestamp() - measured, 1) if measured else None
stale = age is None or age > max_age

print(f"Datei          {path}")
print(f"Collector      {coll.get('name')} {coll.get('version')} auf {coll.get('host')} "
      f"(PID {coll.get('pid')}, Sequenz {coll.get('sequence')})")
print(f"Messzeitpunkt  {coll.get('measured_at')}")
print(f"Datenalter     {age} s (Grenze {max_age} s) -> {'VERALTET' if stale else 'frisch'}")
print(f"Erfassung      {coll.get('status')} | Docker erreichbar: "
      f"{(coll.get('docker') or {}).get('reachable')} | Messdauer {coll.get('duration_ms')} ms")
print()
print(f"{'SERVICE':<10} {'ZUSTAND':<11} {'HEALTH':<10} {'STATUS':<10} {'NEUSTARTS':<10} BEGRUENDUNG")
for entry in snap.get("services", []):
    health = (entry.get("health") or {}).get("state") or "-"
    container = entry.get("container") or {}
    status = "UNKNOWN (veraltet)" if stale else entry.get("status", "?")
    print(f"{entry.get('service',''):<10} {str(entry.get('process_state') or '-'):<11} "
          f"{health:<10} {status:<10} {str(container.get('restart_count') if container else '-'):<10} "
          f"{entry.get('status_reason','')}")

for entry in snap.get("services", []):
    logs = entry.get("logs") or {}
    if logs.get("error"):
        print(f"\nLOGZUGRIFF {entry['service']}: {logs['error']}")
    last = logs.get("last_error")
    if last:
        print(f"\nLetzter Fehler {entry['service']} ({logs.get('error_count')} im Fenster)")
        print(f"  {last.get('ts')} [{last.get('stream')}] {last.get('message')}")

if show_logs:
    for entry in snap.get("services", []):
        lines = (entry.get("logs") or {}).get("lines") or []
        print(f"\n--- Logs {entry['service']} ({len(lines)} Zeilen) ---")
        for line in lines:
            print(f"  {line.get('ts')} [{line.get('level')}] {line.get('message')}")

for problem in snap.get("errors", []):
    print(f"\nFEHLER {problem}")
for extra in snap.get("unexpected_containers", []):
    print(f"\nHINWEIS zusaetzlicher Container im Projekt: {extra.get('name')} ({extra.get('service')})")

if stale:
    print("\nErgebnis: Daten sind aelter als erlaubt. Als UNKNOWN werten, nicht als gesund.")
    sys.exit(2)
if coll.get("status") != "ok":
    print("\nErgebnis: Datenerfassung degradiert. Zustaende sind nicht verlaesslich.")
    sys.exit(1)
print("\nErgebnis: Snapshot frisch, Datenerfassung ok.")
PY
exit $?
