#!/usr/bin/env bash
# Installiert den Host-Collector als systemd-Dienst auf dem Ubuntu-Host.
# Aufruf:   sudo ./scripts/install-collector.sh
# Entfernen: sudo ./scripts/install-collector.sh --uninstall
set -euo pipefail

SERVICE_NAME="hf-ops-collector"
APP_DIR="/opt/hf-ops-collector"
CONF_DIR="/etc/hf-ops-collector"
STATE_DIR="/var/lib/hf-ops-collector/state"
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
  say "Programmdateien entfernen (${APP_DIR})"
  rm -rf "${APP_DIR}"
  say "Konfiguration und Zustandsdaten bleiben erhalten:"
  printf '    %s\n    %s\n' "${CONF_DIR}" "${STATE_DIR}"
  printf '    Vollstaendig entfernen: sudo rm -rf %s %s\n' "${CONF_DIR}" "/var/lib/hf-ops-collector"
  exit 0
fi

command -v python3 >/dev/null || die "python3 fehlt. Installieren: sudo apt-get install -y python3"
command -v docker  >/dev/null || die "docker fehlt oder ist nicht im PATH von root."
[ -f "${SRC_DIR}/hf_collector.py" ] || die "hf_collector.py nicht gefunden in ${SRC_DIR}"

say "Logik ohne Docker pruefen (Selbsttest)"
python3 "${SRC_DIR}/hf_collector.py" --selftest

say "Verzeichnisse anlegen"
install -d -m 0755 "${APP_DIR}" "${CONF_DIR}" "${STATE_DIR}"

say "Programmdateien kopieren nach ${APP_DIR}"
install -m 0755 "${SRC_DIR}/hf_collector.py" "${APP_DIR}/hf_collector.py"
[ -f "${SRC_DIR}/README.md" ] && install -m 0644 "${SRC_DIR}/README.md" "${APP_DIR}/README.md"

if [ -f "${CONF_DIR}/collector.env" ]; then
  say "Konfiguration bleibt unveraendert: ${CONF_DIR}/collector.env"
else
  say "Konfiguration anlegen: ${CONF_DIR}/collector.env"
  install -m 0644 "${SRC_DIR}/collector.env.example" "${CONF_DIR}/collector.env"
fi

say "systemd-Unit installieren"
install -m 0644 "${SRC_DIR}/systemd/${SERVICE_NAME}.service" "${UNIT_PATH}"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

say "Auf den ersten Snapshot warten"
SNAPSHOT="${STATE_DIR}/snapshot.json"
for _ in $(seq 1 20); do
  [ -s "${SNAPSHOT}" ] && break
  sleep 1
done

if [ -s "${SNAPSHOT}" ]; then
  say "Snapshot vorhanden: ${SNAPSHOT}"
  "${SRC_DIR}/scripts/check-snapshot.sh" || true
else
  printf 'FEHLER: Nach 20s kein Snapshot. Logs lesen:\n' >&2
  printf '    sudo journalctl -u %s -n 30 --no-pager\n' "${SERVICE_NAME}" >&2
  exit 1
fi

cat <<EOF

Installation abgeschlossen.

  Status        sudo systemctl status ${SERVICE_NAME}
  Logs          sudo journalctl -u ${SERVICE_NAME} -f
  Snapshot      ${SNAPSHOT}
  Pruefen       ./scripts/check-snapshot.sh
  Neu starten   sudo systemctl restart ${SERVICE_NAME}

Mount fuer das Dashboard (read-only, kein Docker-Socket):
  volumes:
    - ${STATE_DIR}:/data/collector:ro
EOF
