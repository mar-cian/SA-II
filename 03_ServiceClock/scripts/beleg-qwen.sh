#!/usr/bin/env bash
# beleg-qwen.sh - legt einen Qwen-Austausch als Beleg ab, der ueber Open WebUI
# gefuehrt wurde. Gegenstueck zu frag-qwen.sh fuer den Fall, dass du die
# Oberflaeche statt der API benutzt.
#
# Die Antwort wird von der Standardeingabe gelesen, damit du sie einfach
# einfuegen kannst. Abschluss mit Strg-D in einer leeren Zeile.
#
# Aufruf:
#   ./scripts/beleg-qwen.sh <kurzname> <promptdatei> [modell]
#   ./scripts/beleg-qwen.sh healthcheck prompts/03_healthcheck_curl.txt
#
#   Eigener Prompt, nicht aus einer Datei:
#   ./scripts/beleg-qwen.sh nachfrage - coder-genau
#   (dann erst den Prompt einfuegen, Strg-D, danach die Antwort, Strg-D)
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "${SELF}/.." && pwd)"
BELEGE="${APP}/belege/qwen"

NAME="${1:-}"
FILE="${2:-}"
MODEL="${3:-coder-schnell}"
QUELLE="${QUELLE:-Open WebUI auf 127.0.0.1:3000}"

if [ -z "${NAME}" ] || [ -z "${FILE}" ]; then
  printf 'Aufruf: %s <kurzname> <promptdatei|-> [modell]\n' "$0" >&2
  exit 1
fi

if [ "${FILE}" = "-" ]; then
  printf 'Prompt einfuegen, dann Strg-D:\n' >&2
  PROMPT="$(cat)"
else
  [ -r "${FILE}" ] || { printf 'FEHLER: %s nicht lesbar\n' "${FILE}" >&2; exit 1; }
  PROMPT="$(cat "${FILE}")"
fi
[ -n "${PROMPT}" ] || { printf 'FEHLER: leerer Prompt\n' >&2; exit 1; }

printf '\nAntwort von Qwen einfuegen, dann Strg-D in einer leeren Zeile:\n' >&2
ANTWORT="$(cat)"
if [ -z "${ANTWORT}" ]; then
  printf 'FEHLER: leere Antwort, nichts gespeichert.\n' >&2
  exit 1
fi

mkdir -p "${BELEGE}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="${BELEGE}/${STAMP}_${NAME}"

{
  printf '# Prompt an Qwen\n'
  printf '# Zeitpunkt (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# Modell: %s\n' "${MODEL}"
  printf '# Quelle: %s\n' "${QUELLE}"
  printf '# Zeichen: %s\n' "${#PROMPT}"
  printf '# ---\n'
  printf '%s\n' "${PROMPT}"
} > "${BASE}_prompt.txt"

{
  printf '# Antwort von Qwen\n'
  printf '# Zeitpunkt (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# Modell: %s\n' "${MODEL}"
  printf '# Quelle: %s, Antwort von Hand uebernommen\n' "${QUELLE}"
  printf '# Prompt: %s_prompt.txt\n' "$(basename "${BASE}")"
  printf '# Hinweis: woertlich eingefuegt, keine inhaltliche Nachbearbeitung.\n'
  printf '# Zeichen: %s\n' "${#ANTWORT}"
  printf '# ---\n\n'
  printf '%s\n' "${ANTWORT}"
} > "${BASE}_antwort.md"

printf '\n--- Belege geschrieben ---\n'
printf '  %s_prompt.txt   (%s Zeichen)\n' "${BASE}" "${#PROMPT}"
printf '  %s_antwort.md   (%s Zeichen)\n' "${BASE}" "${#ANTWORT}"
printf '\nNaechster Schritt: Vorschlag in QWEN_PROTOKOLL.md eintragen,\n'
printf 'mit eigener Pruefung und Entscheidung.\n'
