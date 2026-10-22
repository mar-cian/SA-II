#!/usr/bin/env bash
# frag-qwen.sh - schickt einen Prompt an das lokale Ollama und legt Prompt,
# Antwort und Metadaten als Beleg ab. Damit ist das Entscheidungsprotokoll
# nachweisbar und nicht nachtraeglich aufgeschrieben.
#
# Aufruf:
#   ./scripts/frag-qwen.sh <kurzname> <promptdatei> [modell]
#   echo "Frage" | ./scripts/frag-qwen.sh <kurzname> - [modell]
#
# Beispiel:
#   ./scripts/frag-qwen.sh review prompts/review.txt
#   ./scripts/frag-qwen.sh review prompts/review.txt coder-genau
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "${SELF}/.." && pwd)"
BELEGE="${APP}/belege/qwen"
OLLAMA="${OLLAMA_URL:-http://127.0.0.1:8080}"
NUM_PREDICT="${NUM_PREDICT:-700}"
# Kontextfenster. 4096 ist die Vorgabe aus dem Aufgabenblatt. Fuer einen langen
# Prompt bewusst erhoehen und im Protokoll festhalten: NUM_CTX=8192 ./frag-qwen.sh ...
NUM_CTX="${NUM_CTX:-4096}"
TIMEOUT="${TIMEOUT:-300}"

NAME="${1:-}"
FILE="${2:-}"
MODEL="${3:-coder-schnell}"

if [ -z "${NAME}" ] || [ -z "${FILE}" ]; then
  printf 'Aufruf: %s <kurzname> <promptdatei|-> [modell]\n' "$0" >&2
  exit 1
fi

if [ "${FILE}" = "-" ]; then
  PROMPT="$(cat)"
else
  [ -r "${FILE}" ] || { printf 'FEHLER: %s nicht lesbar\n' "${FILE}" >&2; exit 1; }
  PROMPT="$(cat "${FILE}")"
fi
[ -n "${PROMPT}" ] || { printf 'FEHLER: leerer Prompt\n' >&2; exit 1; }

mkdir -p "${BELEGE}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="${BELEGE}/${STAMP}_${NAME}"

# Prompt als Beleg sichern, bevor gefragt wird
{
  printf '# Prompt an Qwen\n# Zeitpunkt (UTC): %s\n# Modell: %s\n# num_predict: %s | num_ctx: %s | Zeichen: %s\n# ---\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${MODEL}" "${NUM_PREDICT}" "${NUM_CTX}" "${#PROMPT}"
  printf '%s\n' "${PROMPT}"
} > "${BASE}_prompt.txt"

REQUEST="$(python3 -c '
import json, os, sys
print(json.dumps({
    "model": sys.argv[1],
    "stream": False,
    "messages": [{"role": "user", "content": sys.stdin.read()}],
    "options": {"num_predict": int(sys.argv[2]), "num_ctx": int(sys.argv[3])},
}))' "${MODEL}" "${NUM_PREDICT}" "${NUM_CTX}" <<< "${PROMPT}")"

printf 'Frage %s (%s Zeichen Prompt), das kann eine Weile dauern ...\n' \
  "${MODEL}" "${#PROMPT}"
START=$(date +%s)
RESPONSE="$(curl -sS --max-time "${TIMEOUT}" "${OLLAMA}/api/chat" \
  -H 'Content-Type: application/json' -d "${REQUEST}" 2>&1)"
RC=$?
DAUER=$(( $(date +%s) - START ))

if [ "${RC}" -ne 0 ] || [ -z "${RESPONSE}" ]; then
  {
    printf '# Antwort von Qwen\n# Zeitpunkt (UTC): %s\n# FEHLGESCHLAGEN, Exit-Code %s nach %ss\n# ---\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${RC}" "${DAUER}"
    printf '%s\n' "${RESPONSE}"
  } > "${BASE}_antwort.md"
  printf 'FEHLER: keine Antwort. Pruefen: curl -fsS %s/api/tags\n' "${OLLAMA}" >&2
  printf 'Beleg: %s_antwort.md\n' "${BASE}" >&2
  exit 1
fi

printf '%s' "${RESPONSE}" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print('# Keine verwertbare JSON-Antwort:'); print(raw[:2000]); raise SystemExit(1)
content = (data.get('message') or {}).get('content', '')
if not content:
    print('# Leere Antwort. Rohdaten:'); print(json.dumps(data, indent=2)[:2000]); raise SystemExit(1)
print(content)
" > "${BASE}_antwort_roh.txt"
RC2=$?

{
  printf '# Antwort von Qwen\n'
  printf '# Zeitpunkt (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# Modell: %s | Dauer: %ss | Prompt: %s_prompt.txt\n' \
    "${MODEL}" "${DAUER}" "$(basename "${BASE}")"
  printf '# Hinweis: unveraendert uebernommen, keine Nachbearbeitung.\n'
  printf '# ---\n\n'
  cat "${BASE}_antwort_roh.txt"
} > "${BASE}_antwort.md"
rm -f "${BASE}_antwort_roh.txt"

printf '\n--- Antwort ---\n'
sed -n '7,$p' "${BASE}_antwort.md"
printf '\n--- Belege ---\n  %s_prompt.txt\n  %s_antwort.md\n' "${BASE}" "${BASE}"
printf 'Dauer: %ss\n' "${DAUER}"
exit "${RC2}"
