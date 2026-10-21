#!/usr/bin/env bash
# Einen einzelnen Messdurchgang von Hand ausfuehren.
# Gedacht fuer Troubleshooting-Stufe 3: "Collector einmal manuell ausfuehren".
#
# Aufruf:
#   ./scripts/run-once.sh            einmal messen, Snapshot schreiben, Tabelle zeigen
#   ./scripts/run-once.sh --stdout   einmal messen, nur JSON ausgeben, nichts schreiben
#
# Hinweis: Ein manueller Lauf schreibt in dieselbe Datei wie der Dienst. Fuer eine
# reine Diagnose ohne Nebenwirkung --stdout verwenden.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="/etc/hf-ops-collector/collector.env"

# Installierte Konfiguration verwenden, sonst das Beispiel aus dem Quellordner.
if [ -r "${CONF}" ]; then
  set -a; . "${CONF}"; set +a
elif [ -r "${SRC_DIR}/collector.env.example" ]; then
  set -a; . "${SRC_DIR}/collector.env.example"; set +a
fi

# Docker und das Zustandsverzeichnis verlangen root. Als normaler Benutzer wird
# der Lauf einmalig ueber sudo wiederholt, damit die HFC_-Variablen erhalten bleiben.
if [ "$(id -u)" -ne 0 ]; then
  HFC_VARS=()
  while IFS= read -r line; do HFC_VARS+=("$line"); done < <(env | sed -n 's/^\(HFC_[A-Z_]*=.*\)$/\1/p')
  exec sudo env ${HFC_VARS[@]+"${HFC_VARS[@]}"} HFC_DOCKER_SUDO=0 \
    python3 "${SRC_DIR}/hf_collector.py" --once "$@"
fi

export HFC_DOCKER_SUDO=0
exec python3 "${SRC_DIR}/hf_collector.py" --once "$@"
