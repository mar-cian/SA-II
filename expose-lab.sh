#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Aufruf: sudo bash $0 UBUNTU_IP KALI_IP [8081 8082 8083]" >&2
  exit 2
}
[[ $# -ge 2 ]] || usage
[[ $EUID -eq 0 ]] || { echo 'Bitte mit sudo ausführen.' >&2; exit 1; }
ubuntu_ip=$1
kali_ip=$2
shift 2
ports=("$@")
[[ ${#ports[@]} -gt 0 ]] || ports=(8081 8082 8083)
for command in nginx python3 ip systemctl flock; do
  command -v "$command" >/dev/null || { echo "Voraussetzung fehlt: $command" >&2; exit 1; }
done
exec 9>/run/lock/hf-lab-expose.lock
flock -n 9 || { echo 'Eine andere Einrichtung läuft bereits.' >&2; exit 1; }

python3 - "$ubuntu_ip" "$kali_ip" <<'PY'
import ipaddress, json, subprocess, sys
addresses = [ipaddress.IPv4Address(value) for value in sys.argv[1:]]
for address in addresses:
    if address.is_loopback or address.is_multicast or address.is_unspecified or address.is_reserved:
        raise SystemExit('Eine gültige Unicast-LAN-Adresse ist erforderlich.')
if addresses[0] == addresses[1]:
    raise SystemExit('Ubuntu und Kali müssen verschiedene Adressen haben.')
interfaces = json.loads(subprocess.check_output(['ip', '-j', '-4', 'address', 'show']))
local = {entry['local'] for interface in interfaces for entry in interface.get('addr_info', [])}
if str(addresses[0]) not in local:
    raise SystemExit('Die Ubuntu-IP ist auf diesem Host nicht eingerichtet.')
PY

declare -A seen=()
for port in "${ports[@]}"; do
  case "$port" in 8081|8082|8083) ;; *) echo "Unzulässiger Port: $port" >&2; exit 2 ;; esac
  [[ -z ${seen[$port]+x} ]] || { echo "Doppelter Port: $port" >&2; exit 2; }
  seen[$port]=1
done

systemctl is-active --quiet nginx || { echo 'Nginx muss installiert und gestartet sein.' >&2; exit 1; }
nginx -t
# Die feste Zieldatei wird nur überschrieben, wenn sie diesem Skript gehört.
target=/etc/nginx/conf.d/hf-lab-expose.conf
if [[ -L $target ]]; then
  echo "Abbruch: $target ist ein symbolischer Link." >&2
  exit 1
fi
if [[ -f $target ]] && ! head -n 1 "$target" | grep -qx '# Managed by expose-lab.sh'; then
  echo "Abbruch: $target enthält eine fremde Konfiguration." >&2
  exit 1
fi
if [[ ! -f $target ]]; then
  python3 - "$ubuntu_ip" "${ports[@]}" <<'PY'
import socket, sys
for port in sys.argv[2:]:
    with socket.socket() as listener:
        try:
            listener.bind((sys.argv[1], int(port)))
        except OSError as error:
            raise SystemExit(f'LAN-Port {port} bereits belegt oder nicht bindbar: {error}')
PY
fi

temporary=$(mktemp -d)
had_previous=0
installed=0
committed=0
cleanup() {
  result=$?
  trap - EXIT
  if [[ $installed -eq 1 && $committed -eq 0 ]]; then
    if [[ $had_previous -eq 1 ]]; then
      cp "$temporary/previous.conf" "$target"
    else
      rm -f "$target"
    fi
    nginx -t && systemctl reload nginx || echo 'Nginx-Rücknahme bitte manuell prüfen.' >&2
  fi
  rm -rf "$temporary"
  exit "$result"
}
trap cleanup EXIT
if [[ -f $target ]]; then
  cp "$target" "$temporary/previous.conf"
  had_previous=1
fi

printf '%s\n' '# Managed by expose-lab.sh' > "$temporary/new.conf"
for port in "${ports[@]}"; do
  cat >> "$temporary/new.conf" <<EOF
server {
    listen ${ubuntu_ip}:${port};
    server_name _;
    allow ${kali_ip};
    allow ${ubuntu_ip};
    deny all;
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Lab-Request \$http_x_lab_request;
        proxy_connect_timeout 5s;
        proxy_read_timeout 110s;
    }
}
EOF
done

# Vorherige Konfiguration ausserhalb von conf.d aufbewahren.
if [[ $had_previous -eq 1 ]]; then
  install -d -m 700 /var/backups/hf-lab-expose
  backup=$(mktemp /var/backups/hf-lab-expose/previous.XXXXXXXX)
  cp "$temporary/previous.conf" "$backup"
  echo "Sicherung: $backup"
fi
installed=1
install -m 644 "$temporary/new.conf" "$target"
nginx -t
# Sicherstellen, dass die Standardkonfiguration conf.d tatsächlich einbindet.
nginx -T > "$temporary/effective.conf" 2>&1
grep -Fq "# configuration file ${target}:" "$temporary/effective.conf" || {
  echo 'Die aktive nginx.conf bindet conf.d nicht ein.' >&2; exit 1;
}
systemctl reload nginx

# Ein erfolgreicher Reload-Aufruf allein beweist noch keinen aktiven Listener.
# Prüft die Verbindung und den HTTP-Antwortbeginn über die LAN-Adresse.
python3 - "$ubuntu_ip" "${ports[@]}" <<'PY'
import socket, sys, time
host = sys.argv[1]
for value in sys.argv[2:]:
    port = int(value)
    for attempt in range(10):
        try:
            with socket.create_connection((host, port), timeout=2) as connection:
                connection.sendall(f'GET / HTTP/1.0\r\nHost: {host}\r\n\r\n'.encode())
                response = connection.recv(4096)
            line = response.split(b'\r\n', 1)[0].decode(errors='replace')
            if not line.startswith('HTTP/'):
                raise ValueError('Keine HTTP-Antwort')
            if line.split()[1] != '200':
                raise ValueError(line)
            print(f'Erreichbar: http://{host}:{port}/ ({line})')
            break
        except (OSError, ValueError) as error:
            if attempt == 9:
                raise SystemExit(f'Prüfung auf Port {port} fehlgeschlagen: {error}')
            time.sleep(1)
PY
committed=1
echo 'Nginx-Freigabe eingerichtet. Firewall und Zugriff von Kali separat prüfen.'
