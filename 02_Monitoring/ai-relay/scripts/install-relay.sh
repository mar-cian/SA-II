#!/usr/bin/env bash
# Installiert das AI-Relay als systemd-Dienst auf dem Ubuntu-Host.
# Aufruf:    sudo ./scripts/install-relay.sh
# Entfernen: sudo ./scripts/install-relay.sh --uninstall
set -euo pipefail

SERVICE_NAME="hf-ops-ai-relay"
APP_DIR="/opt/hf-ops-ai-relay"
CONF_DIR="/etc/hf-ops-ai-relay"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { printf '==> %s\n' "$*"; }
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Bitte mit sudo ausfuehren: sudo $0 $*"

if [ "${1:-}" = "--uninstall" ]; then
  say "Dienst stoppen und entfernen"
  systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${UNIT_PATH}"
  systemctl daemon-reload
  rm -rf "${APP_DIR}"
  say "Konfiguration bleibt erhalten: ${CONF_DIR}"
  printf '    Vollstaendig entfernen: sudo rm -rf %s\n' "${CONF_DIR}"
  exit 0
fi

command -v python3 >/dev/null || die "python3 fehlt."
[ -f "${SRC_DIR}/hf_ai_relay.py" ] || die "hf_ai_relay.py nicht gefunden in ${SRC_DIR}"

say "Eingabepruefung testen (ohne Ollama)"
python3 "${SRC_DIR}/hf_ai_relay.py" --selftest

say "Ollama auf dem Host pruefen"
if curl -fsS --max-time 5 "http://127.0.0.1:8080/api/tags" >/dev/null 2>&1; then
  MODELS="$(curl -fsS --max-time 5 http://127.0.0.1:8080/api/tags \
            | python3 -c 'import json,sys; print(", ".join(m.get("name","?") for m in json.load(sys.stdin).get("models",[])) or "keine")' 2>/dev/null || echo '?')"
  say "Ollama erreichbar. Vorhandene Modelle: ${MODELS}"
else
  printf 'WARNUNG: Ollama unter 127.0.0.1:8080 nicht erreichbar.\n'
  printf '         Das Relay wird trotzdem installiert und meldet den Zustand sauber.\n'
  printf '         Pruefen: curl -fsS http://127.0.0.1:8080/api/tags\n'
fi

say "Verzeichnisse anlegen"
install -d -m 0755 "${APP_DIR}" "${CONF_DIR}"

say "Programmdateien kopieren nach ${APP_DIR}"
install -m 0755 "${SRC_DIR}/hf_ai_relay.py" "${APP_DIR}/hf_ai_relay.py"
[ -f "${SRC_DIR}/README.md" ] && install -m 0644 "${SRC_DIR}/README.md" "${APP_DIR}/README.md"

if [ -f "${CONF_DIR}/relay.env" ]; then
  say "Konfiguration bleibt unveraendert: ${CONF_DIR}/relay.env"
else
  say "Konfiguration anlegen: ${CONF_DIR}/relay.env"
  install -m 0644 "${SRC_DIR}/relay.env.example" "${CONF_DIR}/relay.env"
fi

say "systemd-Unit installieren"
install -m 0644 "${SRC_DIR}/systemd/${SERVICE_NAME}.service" "${UNIT_PATH}"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
  say "Dienst laeuft"
  "${SRC_DIR}/scripts/check-relay.sh" || true
else
  printf 'FEHLER: Dienst laeuft nicht. Logs lesen:\n' >&2
  printf '    sudo journalctl -u %s -n 30 --no-pager\n' "${SERVICE_NAME}" >&2
  exit 1
fi

BIND="$(. "${CONF_DIR}/relay.env" 2>/dev/null; echo "${AIR_BIND_HOST:-172.31.240.1}:${AIR_BIND_PORT:-8899}")"
cat <<EOF

Installation abgeschlossen.

  Status        sudo systemctl status ${SERVICE_NAME}
  Logs          sudo journalctl -u ${SERVICE_NAME} -f
  Pruefen       ./scripts/check-relay.sh
  Lauscht auf   ${BIND}

Hinweis: Das Relay lauscht auf dem Gateway des Dashboard-Netzes. Solange dieses
Netz noch nicht existiert (Dashboard nie gestartet), ist die Adresse am Host
noch nicht vorhanden. Der Dienst bindet trotzdem (IP_FREEBIND) und ist
erreichbar, sobald das Netz da ist.
EOF
