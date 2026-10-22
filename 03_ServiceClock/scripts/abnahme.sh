#!/usr/bin/env bash
# abnahme.sh - fuehrt die Abnahme aus dem Aufgabenblatt aus und sammelt Belege.
#
# Geprueft wird: Build, Erreichbarkeit, dynamische Information, /health,
# Logs, non-root, Prozessneustart, Containerneuerstellung, unerwarteter
# Prozessabbruch mit Restart Policy.
#
# Aufruf: sudo ./scripts/abnahme.sh
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "${SELF}/.." && pwd)"
DIR="${APP}/belege/abnahme"
URL="${CLOCK_URL:-http://127.0.0.1:8095}"

[ "$(id -u)" -eq 0 ] || { printf 'FEHLER: bitte mit sudo ausfuehren: sudo %s\n' "$0" >&2; exit 1; }
mkdir -p "${DIR}"
cd "${APP}" || exit 1

ts()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
step() { printf '\n[%s] === %s ===\n' "$(ts)" "$*"; }
note() { printf '[%s] %s\n' "$(ts)" "$*"; }
PROTOKOLL="${DIR}/abnahme_$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "${PROTOKOLL}") 2>&1

cid()   { docker compose ps -q clock 2>/dev/null; }
fakten() {
  local id; id="$(cid)"
  if [ -z "${id}" ]; then printf 'kein Container vorhanden\n'; return; fi
  docker inspect --format \
    'ID={{slice .Id 0 12}} Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}keiner{{end}} RestartCount={{.RestartCount}} Policy={{.HostConfig.RestartPolicy.Name}} User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}}' \
    "${id}"
}

pruefung() {
  local label="$1"
  printf -- '--- Funktionspruefung: %s ---\n' "${label}"
  printf 'Fakten:   %s\n' "$(fakten)"
  printf 'GET /         HTTP %s\n' \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${URL}/")"
  printf 'GET /health   HTTP %s  ' \
    "$(curl -s -o /tmp/ab_health.json -w '%{http_code}' --max-time 5 "${URL}/health")"
  python3 -c "
import json
try:
    d = json.load(open('/tmp/ab_health.json'))
    print('status=%s uptime=%ss anfragen=%s' % (d['status'], d['uptime_seconds'], d['requests_served']))
except Exception as exc:
    print('keine JSON-Antwort:', exc)"
  printf 'GET /gibtsnicht HTTP %s (erwartet 404)\n' \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${URL}/gibtsnicht")"
  printf 'POST /        HTTP %s (erwartet 405)\n' \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST "${URL}/")"
  printf 'Benutzer im Container: '
  docker compose exec -T clock id 2>/dev/null || printf '(exec nicht moeglich)\n'
}

printf 'Abnahmeprotokoll Service Clock\n'
printf 'Protokoll: %s\n' "${PROTOKOLL}"
printf 'Adresse:   %s\n' "${URL}"

step "1. Build und Start"
docker compose up -d --build
docker compose ps
note "12 s warten, Startphase und Healthcheck abwarten"
sleep 12
docker images --format '  {{.Repository}}:{{.Tag}}  {{.ID}}  {{.Size}}' | grep service-clock

step "2. Funktionspruefung im Normalbetrieb"
pruefung "nach dem Start"

step "3. Dynamische Information veraendert sich"
curl -fsS --max-time 5 "${URL}/api/clock" > /tmp/ab_a.json
sleep 4
curl -fsS --max-time 5 "${URL}/api/clock" > /tmp/ab_b.json
python3 - <<'PY'
import json
a = json.load(open('/tmp/ab_a.json')); b = json.load(open('/tmp/ab_b.json'))
rows = [
    ("now",             a["now"],              b["now"],              a["now"] != b["now"]),
    ("uptime_seconds",  a["uptime_seconds"],   b["uptime_seconds"],   b["uptime_seconds"] > a["uptime_seconds"]),
    ("requests_served", a["requests_served"],   b["requests_served"],  b["requests_served"] > a["requests_served"]),
    ("started_at",      a["started_at"],       b["started_at"],       a["started_at"] == b["started_at"]),
]
for name, v1, v2, ok in rows:
    print(f"  {'ok  ' if ok else 'FAIL'} {name:<16} {v1}  ->  {v2}")
PY

step "4. Logs"
docker compose logs --tail 15 clock

step "5. Prozessneustart (docker compose restart)"
VORHER="$(fakten)"
note "vorher:  ${VORHER}"
docker compose restart clock
sleep 12
note "nachher: $(fakten)"
note "Erwartung: gleiche ID, RestartCount unveraendert, Laufzeit und Zaehler zurueckgesetzt."
pruefung "nach Prozessneustart"

step "6. Unerwarteter Prozessabbruch (SIGKILL) und Restart Policy"
note "vorher:  $(fakten)"
docker compose kill -s SIGKILL clock
sleep 2
note "direkt danach: $(fakten)"
note "15 s warten, Restart Policy soll selbst neu starten"
sleep 15
note "nachher: $(fakten)"
note "Erwartung: gleiche ID, RestartCount um 1 hoeher, Anwendung wieder erreichbar."
note "Das ist der Nachweis der automatischen Wiederanlaufregel. down und up -d"
note "allein waere keiner, weil der Start dabei von Hand ausgeloest wird."
pruefung "nach unerwartetem Abbruch"

step "7. Containerneuerstellung (down, dann up -d)"
note "vorher:  $(fakten)"
docker compose down
printf 'Dashboard waehrend des Abbaus: HTTP %s (000 heisst: wirklich weg)\n' \
  "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "${URL}/health")"
docker compose up -d
sleep 12
note "nachher: $(fakten)"
note "Erwartung: NEUE Container-ID, RestartCount wieder 0."
pruefung "nach Containerneuerstellung"

step "8. Datenhaltung bei zustandsloser Anwendung"
note "Kein Volume vorhanden:"
docker inspect --format '  Mounts: {{if .Mounts}}{{range .Mounts}}{{.Source}} -> {{.Destination}} {{end}}{{else}}keine{{end}}' "$(cid)"
note "Zurueckgesetzt wurden: started_at, uptime_seconds, requests_served."
note "Unveraendert: SERVICE_NAME und CLOCK_TZ, weil sie aus der Konfiguration kommen."
curl -fsS --max-time 5 "${URL}/api/clock" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f\"  service={d['service']} timezone={d['timezone']} started_at={d['started_at']}\")
print(f\"  uptime={d['uptime_seconds']}s anfragen={d['requests_served']}\")"

step "Abschluss"
note "Protokoll: ${PROTOKOLL}"
note "Noch von Hand: Codeaenderung, dann 'docker compose up -d --build', und"
note "pruefen dass die Image-ID wechselt und die Aenderung sichtbar wird."
