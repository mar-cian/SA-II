#!/usr/bin/env bash
# review-prompt.sh - baut den Review-Prompt aus dem Aufgabenblatt zusammen und
# haengt die tatsaechlichen Dateien an. Gibt alles auf stdout aus.
#
# Das Kontextfenster ist auf 4096 begrenzt. Alle Dateien zusammen sind dafuer
# zu lang und wuerden abgeschnitten, deshalb standardmaessig nur Dockerfile und
# compose.yaml. Den Code getrennt pruefen lassen.
#
# Aufruf:
#   ./scripts/review-prompt.sh            Dockerfile und compose.yaml (Vorgabe)
#   ./scripts/review-prompt.sh logik      app.py ohne CSS, passt in 4096
#   ./scripts/review-prompt.sh code       nur app.py, vollstaendig
#   ./scripts/review-prompt.sh alles      alles, wird vermutlich gekuerzt
#
#   ./scripts/review-prompt.sh      | ./scripts/frag-qwen.sh review_config -
#   ./scripts/review-prompt.sh code | ./scripts/frag-qwen.sh review_code -
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "${SELF}/.." && pwd)"
WAS="${1:-config}"

cat <<'EOF'
Pruefe die folgenden Dateien auf Security, Zuverlaessigkeit, Wartbarkeit und
unnoetige Komplexitaet.
Trenne CRITICAL, IMPROVEMENT und OPTIONAL.
Nenne jeweils Fundstelle, Auswirkung und ueberpruefbaren Fix.
Behaupte nicht, Tests ausgefuehrt zu haben.
Antworte knapp.

Es handelt sich um eine kleine zustandslose Anwendung, die ihren eigenen
Betriebszustand anzeigt. Bewusste Entscheidungen: nur Standardbibliothek,
kein Volume, Bindung auf 127.0.0.1, nicht privilegierter Benutzer.

EOF

case "${WAS}" in
  config)
    printf -- '--- Dockerfile ---\n'; cat "${APP}/Dockerfile"
    printf -- '\n--- compose.yaml ---\n'; cat "${APP}/compose.yaml"
    ;;
  logik)
    # app.py ohne den CSS-Block: Stile sind fuer einen Security-Review nicht
    # relevant und machen rund ein Drittel des Textes aus. So passt der Prompt
    # in das Kontextfenster von 4096.
    printf -- '--- app.py, CSS-Block ausgelassen ---\n'
    python3 - "${APP}/app.py" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
print(re.sub(r'STYLE = """.*?"""', 'STYLE = "... CSS ausgelassen ..."', src, flags=re.S))
PYEOF
    ;;
  code)
    printf -- '--- app.py ---\n'; cat "${APP}/app.py"
    ;;
  alles)
    printf -- '--- Dockerfile ---\n'; cat "${APP}/Dockerfile"
    printf -- '\n--- compose.yaml ---\n'; cat "${APP}/compose.yaml"
    printf -- '\n--- app.py ---\n'; cat "${APP}/app.py"
    printf -- '\n' >&2
    printf 'WARNUNG: alles zusammen sprengt 4096 Kontext, die Antwort wird\n' >&2
    printf '         vermutlich gekuerzt. Besser getrennt pruefen lassen.\n' >&2
    ;;
  *)
    printf 'Unbekannt: %s. Erlaubt: config, logik, code, alles\n' "${WAS}" >&2
    exit 1
    ;;
esac
