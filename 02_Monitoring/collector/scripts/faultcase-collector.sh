#!/usr/bin/env bash
# Fehlerfall "Datenerfassung gestoert" nachweisen und wiederherstellen.
# Deckt Auftrag 2, Phase E, Versuch 3 ab: Collector beenden, pruefen dass alte
# Daten NICHT als frisch oder gesund erscheinen, danach wiederherstellen.
#
# Aufruf:
#   sudo ./scripts/faultcase-collector.sh
#   sudo DASHBOARD_URL=http://127.0.0.1:8090/health ./scripts/faultcase-collector.sh
#
# Das Protokoll wird zusaetzlich in eine Datei geschrieben (Beleg fuer die Abgabe).
set -uo pipefail

SERVICE_NAME="hf-ops-collector"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT="${HFC_OUT_DIR:-/var/lib/hf-ops-collector/state}/${HFC_OUT_FILE:-snapshot.json}"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:8090/health}"
WAIT_SECONDS="${WAIT_SECONDS:-35}"
PROTOCOL="${PROTOCOL:-$PWD/nachweis_collector_ausfall_$(date -u +%Y%m%dT%H%M%SZ).log}"

if [ "$(id -u)" -ne 0 ]; then
  printf 'FEHLER: systemctl verlangt root. Aufruf: sudo %s\n' "$0" >&2
  exit 1
fi

exec > >(tee -a "${PROTOCOL}") 2>&1

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
step()  { printf '\n[%s] === %s ===\n' "$(stamp)" "$*"; }
note()  { printf '[%s] %s\n' "$(stamp)" "$*"; }

age_seconds() {
  python3 - "${SNAPSHOT}" <<'PY' 2>/dev/null || echo "n/a"
import json, sys
from datetime import datetime, timezone
with open(sys.argv[1], encoding="utf-8") as handle:
    snap = json.load(handle)
epoch = snap["collector"]["measured_at_epoch"]
print(round(datetime.now(timezone.utc).timestamp() - epoch, 1))
PY
}

dashboard_health() {
  if command -v curl >/dev/null; then
    curl -fsS --max-time 3 "${DASHBOARD_URL}" 2>&1 || printf '(keine Antwort von %s)' "${DASHBOARD_URL}"
  else
    printf '(curl nicht installiert, Dashboard nicht geprueft)'
  fi
}

printf 'Fehlerfall-Protokoll: Datenerfassung gestoert\n'
printf 'Protokolldatei: %s\n' "${PROTOCOL}"
printf 'Snapshot:       %s\n' "${SNAPSHOT}"
printf 'Dashboard:      %s\n' "${DASHBOARD_URL}"

step "Soll-Zustand vor dem Eingriff: Snapshot frisch, Erfassung ok"
"${SRC_DIR}/scripts/check-snapshot.sh"; note "check-snapshot Exit-Code: $?"
note "Dashboard /health: $(dashboard_health)"

step "Eingriff: Collector beenden (systemctl stop ${SERVICE_NAME})"
systemctl stop "${SERVICE_NAME}"
note "Dienststatus: $(systemctl is-active "${SERVICE_NAME}")"
note "Erwartung: Snapshot bleibt unveraendert liegen, sein Alter waechst."

step "Beobachtung ueber ${WAIT_SECONDS}s"
elapsed=0
while [ "${elapsed}" -lt "${WAIT_SECONDS}" ]; do
  note "Alter des Snapshots: $(age_seconds) s | Dashboard: $(dashboard_health)"
  sleep 7
  elapsed=$((elapsed + 7))
done

step "Ist-Zustand im Ausfall: alte Daten duerfen nicht als gesund gelten"
"${SRC_DIR}/scripts/check-snapshot.sh"; rc=$?
note "check-snapshot Exit-Code: ${rc} (erwartet: 2 = veraltet)"
if [ "${rc}" -eq 2 ]; then
  note "BELEG ok: veraltete Daten werden als UNKNOWN gewertet."
else
  note "ACHTUNG: erwartet war Exit-Code 2. HFC_MAX_AGE und WAIT_SECONDS pruefen."
fi

step "Wiederherstellung: Collector starten (systemctl start ${SERVICE_NAME})"
systemctl start "${SERVICE_NAME}"
sleep 8
note "Dienststatus: $(systemctl is-active "${SERVICE_NAME}")"
"${SRC_DIR}/scripts/check-snapshot.sh"; rc=$?
note "check-snapshot Exit-Code: ${rc} (erwartet: 0 = frisch und ok)"
note "Dashboard /health: $(dashboard_health)"

step "Abschluss"
note "Protokoll gespeichert unter ${PROTOCOL}"
note "Letzte Dienstmeldungen:"
journalctl -u "${SERVICE_NAME}" -n 10 --no-pager
