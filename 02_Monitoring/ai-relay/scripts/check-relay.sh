#!/usr/bin/env bash
# Prueft das AI-Relay und gibt den Zustand lesbar aus.
# Beleg fuer das Testprotokoll und Gegenprobe zur Anzeige im Dashboard.
#
# Aufruf:
#   ./scripts/check-relay.sh
#   ./scripts/check-relay.sh --probe     zusaetzlich eine echte Modellanfrage
#
# Exit-Codes
#   0 Relay laeuft, Ollama erreichbar, Vorgabemodell vorhanden
#   1 Relay laeuft, aber Ollama nicht erreichbar oder Modell fehlt
#   2 Relay nicht erreichbar
set -uo pipefail

CONF="/etc/hf-ops-ai-relay/relay.env"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -r "${CONF}" ]; then
  set -a; . "${CONF}"; set +a
elif [ -r "${SRC_DIR}/relay.env.example" ]; then
  set -a; . "${SRC_DIR}/relay.env.example"; set +a
fi
BASE="http://${AIR_BIND_HOST:-172.31.240.1}:${AIR_BIND_PORT:-8899}"

printf 'Relay-Adresse  %s\n' "${BASE}"
if command -v systemctl >/dev/null; then
  printf 'Dienststatus   %s\n' "$(systemctl is-active hf-ops-ai-relay 2>/dev/null || echo 'nicht installiert')"
fi

HEALTH="$(curl -fsS --max-time 6 "${BASE}/health" 2>&1)"
if [ $? -ne 0 ]; then
  printf '\nRelay nicht erreichbar unter %s/health\n' "${BASE}" >&2
  printf '%s\n' "${HEALTH}" >&2
  cat >&2 <<'HINWEIS'

Moegliche Ursachen in dieser Reihenfolge pruefen:
  1. Dienst laeuft nicht:      sudo systemctl status hf-ops-ai-relay
  2. Dashboard-Netz fehlt:     sudo docker network ls | grep hf-ops-dashboard
     Das Relay lauscht auf dem Gateway dieses Netzes. Ohne das Netz existiert
     die Adresse am Host nicht. Dashboard einmal starten.
  3. Adresse passt nicht:      ip -4 addr | grep 172.31.240
     AIR_BIND_HOST in /etc/hf-ops-ai-relay/relay.env muss zum Subnetz in
     02_Monitoring/compose.yaml passen.
HINWEIS
  exit 2
fi

printf '%s\n' "${HEALTH}" | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
print(f"Relay          {data['service']} {data['version']}, Laufzeit {data['uptime_seconds']} s")
print(f"Ollama-Ziel    {data['ollama_url']}")
print(f"Ollama         {'erreichbar' if data['ollama_reachable'] else 'NICHT erreichbar'}"
      + (f" ({data['ollama_detail']})" if data.get('ollama_detail') else ""))
print(f"Modelle da     {', '.join(data['models_available']) or 'keine'}")
print(f"Modelle erlaubt{'':1} {', '.join(data['models_allowed'])}")
print(f"Vorgabemodell  {data['default_model']}")
print(f"Ausgelastet    {'ja' if data['busy'] else 'nein'}")
stats = data.get("stats") or {}
print(f"Anfragen       {stats.get('requests', 0)} gesamt, {stats.get('ok', 0)} ok, "
      f"{stats.get('failed', 0)} fehlgeschlagen")
if stats.get("last_error"):
    print(f"Letzter Fehler {stats['last_error']} ({stats.get('last_at')})")

ok = data["ollama_reachable"]
present = any(m == data["default_model"] or m.split(":", 1)[0] == data["default_model"]
              for m in data["models_available"])
if not ok:
    print("\nErgebnis: Relay laeuft, Ollama ist nicht erreichbar. AI gilt als unavailable.")
    sys.exit(1)
if not present:
    print(f"\nErgebnis: Modell '{data['default_model']}' fehlt in Ollama. AI gilt als unavailable.")
    sys.exit(1)
print("\nErgebnis: Relay laeuft, Ollama erreichbar, Vorgabemodell vorhanden.")
PY
RC=$?

printf '\n--- Gegenprobe: nicht freigegebenes Modell muss abgelehnt werden ---\n'
curl -s -o /tmp/relay_deny.json -w 'HTTP %{http_code} ' --max-time 6 \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3","prompt":"test"}' "${BASE}/v1/analyze"
python3 -c "
import json;d=json.load(open('/tmp/relay_deny.json'));print(d.get('error'),'|',d.get('message'))" 2>/dev/null \
  || printf '(keine JSON-Antwort)\n'

if [ "${1:-}" = "--probe" ] && [ "${RC}" -eq 0 ]; then
  printf '\n--- Echte Modellanfrage (kurz) ---\n'
  START=$(date +%s)
  curl -s --max-time 120 -H 'Content-Type: application/json' \
    -d '{"prompt":"Antworte in genau einem kurzen Satz: bereit.","num_predict":40}' \
    "${BASE}/v1/analyze" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('ok'): print(f\"Modell {d['model']}, {d['duration_ms']} ms:\n  {d['content'][:200]}\")
else: print('Fehler:', d.get('error'), '|', d.get('message'))"
  printf 'Gesamtdauer %ss\n' "$(( $(date +%s) - START ))"
fi

exit "${RC}"
