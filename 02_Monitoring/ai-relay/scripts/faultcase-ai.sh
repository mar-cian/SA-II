#!/usr/bin/env bash
# Fehlerfall "AI nicht erreichbar" nachweisen und wiederherstellen.
# Deckt Auftrag 2, Phase E, Versuch 2 ab: nur die Zieladresse der eigenen
# Anwendung temporaer auf einen unbenutzten lokalen Port setzen. Dashboard und
# Monitoring bleiben benutzbar, AI ist eindeutig unavailable.
#
# Wichtig: Ollama und das Relay werden NICHT angefasst. Geaendert wird nur,
# wohin das Dashboard fragt.
#
# Aufruf:
#   sudo ./scripts/faultcase-ai.sh
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="$(cd "${SRC_DIR}/.." && pwd)"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:8090}"
DEAD_PORT="${DEAD_PORT:-9}"          # unbenutzter lokaler Port
PROTOCOL="${PROTOCOL:-$PWD/nachweis_ai_ausfall_$(date -u +%Y%m%dT%H%M%SZ).log}"

if [ "$(id -u)" -ne 0 ]; then
  printf 'FEHLER: docker compose verlangt hier root. Aufruf: sudo %s\n' "$0" >&2
  exit 1
fi

exec > >(tee -a "${PROTOCOL}") 2>&1

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
step()  { printf '\n[%s] === %s ===\n' "$(stamp)" "$*"; }
note()  { printf '[%s] %s\n' "$(stamp)" "$*"; }

ai_status() {
  curl -fsS --max-time 8 "${DASHBOARD_URL}/api/ai" 2>/dev/null \
    | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('(keine Antwort)'); raise SystemExit
print(f\"status={d.get('status')} ziel={d.get('relay_url')} grund={d.get('message') or '-'}\")" \
    || printf '(Dashboard antwortet nicht)\n'
}

monitoring_usable() {
  curl -fsS --max-time 8 "${DASHBOARD_URL}/api/state" 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
services=', '.join(f\"{s['service']}={s['status']}\" for s in d.get('services',[]))
print(f\"datenlage={d.get('data_status')} services: {services or 'keine'}\")" \
    || printf '(kein Zustand abrufbar)\n'
}

printf 'Fehlerfall-Protokoll: AI nicht erreichbar\n'
printf 'Protokolldatei: %s\n' "${PROTOCOL}"
printf 'Dashboard:      %s\n' "${DASHBOARD_URL}"
printf 'Toter Port:     %s\n' "${DEAD_PORT}"

cd "${COMPOSE_DIR}" || exit 1

step "Soll-Zustand vor dem Eingriff"
note "AI:         $(ai_status)"
note "Monitoring: $(monitoring_usable)"

step "Eingriff: Zieladresse des Dashboards auf unbenutzten Port ${DEAD_PORT}"
note "Ollama und Relay bleiben unveraendert, nur AI_RELAY_URL wird gesetzt."
AI_RELAY_URL="http://127.0.0.1:${DEAD_PORT}" docker compose up -d
sleep 6

step "Ist-Zustand im Ausfall"
note "AI:         $(ai_status)"
note "Monitoring: $(monitoring_usable)"
note "Erwartung: AI status=unavailable mit Begruendung, Monitoring unveraendert nutzbar."

AI_RAW="$(curl -fsS --max-time 8 "${DASHBOARD_URL}/api/ai" 2>/dev/null)"
if printf '%s' "${AI_RAW}" | grep -q '"status": *"unavailable"'; then
  note "BELEG ok: AI wird eindeutig als unavailable gefuehrt."
else
  note "ACHTUNG: erwartet war status=unavailable. Antwort: ${AI_RAW}"
fi
if curl -fsS --max-time 8 "${DASHBOARD_URL}/health" >/dev/null 2>&1; then
  note "BELEG ok: Dashboard-Health weiterhin erreichbar, AI-Ausfall wirft es nicht um."
else
  note "ACHTUNG: Dashboard-Health nicht erreichbar."
fi

step "Analyse im Ausfall anfordern (muss sauber scheitern, nicht haengen)"
curl -s -o /tmp/ai_fail.json -w 'HTTP %{http_code} in %{time_total}s\n' \
  --max-time 30 -X POST "${DASHBOARD_URL}/api/analyze"
python3 -c "
import json
d=json.load(open('/tmp/ai_fail.json'))
print('  error  :', d.get('error'))
print('  message:', d.get('message'))" 2>/dev/null || printf '  (keine JSON-Antwort)\n'

step "Wiederherstellung: korrekte Adresse"
docker compose up -d
sleep 6
note "AI:         $(ai_status)"
note "Monitoring: $(monitoring_usable)"

step "Abschluss"
note "Protokoll gespeichert unter ${PROTOCOL}"
note "Relay-Logs der letzten Minuten:"
journalctl -u hf-ops-ai-relay -n 10 --no-pager 2>/dev/null || true
