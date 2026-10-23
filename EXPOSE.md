# Nginx-Freigabe fuer Kali

Ablauf zu Kapitel 3 des Arbeitsblatts 4. Das Skript `expose-lab.sh` stammt aus
dem Unterrichtspaket und ist unveraendert uebernommen.

Nach dieser Einrichtung brauchst du keinen SSH-Tunnel mehr, um vom Kali auf
Dashboard und Uhr zu kommen.

## Was das Skript tut

Es schreibt `/etc/nginx/conf.d/hf-lab-expose.conf` mit je einem `server`-Block
pro Port:

```
listen <ubuntu-ip>:<port>;
allow <kali-ip>;
allow <ubuntu-ip>;
deny all;
location / { proxy_pass http://127.0.0.1:<port>; ... }
```

Nginx bindet also an die LAN-Adresse, lässt nur Kali und Ubuntu selbst durch und
reicht an die weiterhin auf Loopback gebundene Anwendung weiter. Der Header
`X-Lab-Request` wird mitgegeben. Die Anwendungen bleiben unveraendert auf
`127.0.0.1`.

Vier Dinge, die aus dem Code hervorgehen und beim ersten Lauf stolpern lassen:

- **Nur die Ports 8081, 8082 und 8083 sind zulaessig.** Jeder andere Wert bricht
  mit "Unzulaessiger Port" ab. Der Pruefungsport der Lehrperson wird von ihr
  bereitgestellt, eine eigene Erweiterung ist laut 5.2 nicht verlangt.
- **Die Anwendungen muessen vorher laufen.** Das Skript prueft am Ende per
  HTTP, ob jeder Port antwortet, und erwartet dabei **HTTP 200**.
- **Die Uhr muss ihre Startphase hinter sich haben.** In den ersten 5 Sekunden
  antwortet sie mit 503, das Skript wiederholt zwar zehnmal im Sekundenabstand,
  aber starte sie trotzdem vorher und warte kurz.
- **Ein erneuter Aufruf ersetzt die Portauswahl vollstaendig.** Wer nur 8082
  angibt, verliert 8081 und 8083.

## 1. Voraussetzungen

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
nginx -t
```

Benoetigt werden ausserdem `python3`, `ip`, `systemctl` und `flock`; auf Ubuntu
sind sie vorhanden. Nginx muss `/etc/nginx/conf.d/*.conf` einbinden, das prueft
das Skript selbst.

## 2. Adressen ermitteln

```bash
ip -br -4 address
```

Auf dem Kali ebenfalls, dessen Adresse brauchst du als zweites Argument.

```bash
UBUNTU_IP='192.168.110.61'   # tatsaechliche Werte einsetzen
KALI_IP='192.168.110.xx'
```

## 3. Alle drei Anwendungen starten

```bash
cd ~/workspace/AI-Docker-Lab

sudo docker compose -f 01_Startumgebung/compose.yaml ps -a   # 8081, laeuft schon
cd 02_Monitoring && sudo docker compose up -d && cd ..        # 8082
cd 03_ServiceClock && sudo docker compose up -d && cd ..      # 8083
sleep 15

ss -ltn | grep -E '8081|8082|8083'
curl -sS -o /dev/null -w '8081 HTTP %{http_code}\n' http://127.0.0.1:8081/
curl -sS -o /dev/null -w '8082 HTTP %{http_code}\n' http://127.0.0.1:8082/
curl -sS -o /dev/null -w '8083 HTTP %{http_code}\n' http://127.0.0.1:8083/
```

Alle drei muessen 200 liefern, sonst scheitert die Pruefung am Ende des Skripts.

## 4. Freigabe einrichten

```bash
cd ~/workspace/AI-Docker-Lab
sudo bash expose-lab.sh "$UBUNTU_IP" "$KALI_IP" 8081 8082 8083
```

Erwartet wird je Port eine Zeile `Erreichbar: http://<ubuntu-ip>:<port>/ (HTTP/1.1 200 OK)`
und am Schluss `Nginx-Freigabe eingerichtet.`

## 5. Tests auf Ubuntu

Erst ueber Loopback, dann ueber die LAN-Adresse:

```bash
curl -fsS http://127.0.0.1:8082/api/state | head -c 200; echo
curl --connect-timeout 5 --max-time 10 -fsS "http://${UBUNTU_IP}:8082/api/state" | head -c 200; echo
curl --connect-timeout 5 --max-time 10 -fsS "http://${UBUNTU_IP}:8083/api/info"
```

## 6. Tests auf Kali

Auf dem Kali bezeichnet `127.0.0.1` den Kali selbst, dort ist die Ubuntu-Adresse
noetig.

```bash
UBUNTU_IP='192.168.110.61'
curl --connect-timeout 5 --max-time 10 -fsS "http://${UBUNTU_IP}:8083/api/info"
curl --connect-timeout 5 --max-time 10 -fsS "http://${UBUNTU_IP}:8081/health"
curl -sS -o /dev/null -w 'Dashboard HTTP %{http_code}\n' "http://${UBUNTU_IP}:8082/"
```

Im Browser auf dem Kali dann `http://<ubuntu-ip>:8082` und `http://<ubuntu-ip>:8083`.

### Negativtest

Das Arbeitsblatt nennt als Negativtest eine POST-Anfrage ohne Header mit
erwartetem HTTP 403 und `missing lab header`. **Das gilt fuer das
Referenz-Dashboard der Lehrperson**, das `/api/analyse` anbietet und den Header
`X-Lab-Request` verlangt.

Dieses Projekt hat ein eigenes Dashboard mit `/api/analyze` und ohne
Headerpruefung. Der Negativtest faellt hier also anders aus: die Anfrage wird
angenommen. Das ist eine bewusste Abweichung und gehoert so benannt, nicht
verschwiegen. Was den Zugriff hier begrenzt, ist die `allow`/`deny`-Liste in
Nginx plus die Bindung der Anwendung auf Loopback.

Den Unterschied kannst du zeigen:

```bash
# von einem dritten Rechner, der nicht in der allow-Liste steht
curl --connect-timeout 5 -sS -o /dev/null -w 'HTTP %{http_code}, erwartet 403\n' \
  "http://${UBUNTU_IP}:8082/"
```

Soll das Dashboard den Header ebenfalls verlangen, ist das eine kleine
Ergaenzung; sag Bescheid.

## 7. Firewall

Das Skript aendert keine Firewall-Regeln. Nur noetig, wenn UFW aktiv ist:

```bash
sudo ufw status verbose
sudo ufw allow from "$KALI_IP" to "$UBUNTU_IP" port 8082 proto tcp
sudo ufw allow from "$KALI_IP" to "$UBUNTU_IP" port 8083 proto tcp
sudo ufw allow from "$KALI_IP" to "$UBUNTU_IP" port 8081 proto tcp
```

## 8. Kontrollieren und zuruecknehmen

```bash
sudo cat /etc/nginx/conf.d/hf-lab-expose.conf
sudo nginx -T | grep -A12 'hf-lab-expose'
ss -ltn | grep -E "${UBUNTU_IP}"
```

Vollstaendig entfernen:

```bash
sudo rm /etc/nginx/conf.d/hf-lab-expose.conf
sudo nginx -t && sudo systemctl reload nginx
```

Sicherungen einer vorherigen eigenen Konfiguration legt das Skript unter
`/var/backups/hf-lab-expose/` ab.

## 9. Wenn es klemmt

| Symptom | Ursache und Pruefung |
|---|---|
| `Die Ubuntu-IP ist auf diesem Host nicht eingerichtet` | falsche Adresse, `ip -br -4 address` |
| `Unzulaessiger Port` | nur 8081, 8082 und 8083 sind erlaubt |
| `LAN-Port ... bereits belegt` | ein Wildcard-Listener `0.0.0.0:<port>` steht im Weg, `ss -ltnp` |
| `Pruefung auf Port ... fehlgeschlagen` | die Anwendung antwortet nicht mit 200, siehe Schritt 3 |
| `Die aktive nginx.conf bindet conf.d nicht ein` | `include /etc/nginx/conf.d/*.conf;` fehlt in `nginx.conf` |
| Lokal erreichbar, von Kali nicht | Kali-IP in der `allow`-Liste, UFW, VM-Netzwerk |
| `Abbruch: ... enthaelt eine fremde Konfiguration` | vorhandene Datei stammt nicht vom Skript, erst sichten |

## 10. Belege sammeln

Die Freigabe muss belegt werden. Bereitgestellte Infrastruktur wird laut 7.1
nicht als eigene Entwicklungsleistung bewertet, geprueft werden ihre **richtige
Verwendung** und die **Erklaerung** -- und genau das sind die Belege.

Alles, was auf dem Ubuntu messbar ist, sammelt ein eigener Unterbefehl nach
`belege/12_freigabe_nginx/`:

```bash
cd ~/workspace/AI-Docker-Lab/02_Monitoring
UBUNTU_IP='192.168.110.61' KALI_IP='192.168.110.xx' ./scripts/belege.sh freigabe
```

Nicht mit `sudo` aufrufen, sonst gehoeren die Belegdateien root und lassen sich
schlecht committen. Das Skript ruft `sudo` dort, wo es noetig ist.

| Datei | Belegt |
|---|---|
| `00_eingabe.log` | verwendete Adressen, Ports, Pfad des Skripts |
| `01_skript_lauf.log` | vollstaendige Ausgabe von `expose-lab.sh` mit Exit-Code |
| `02_konfiguration.conf` | erzeugte Nginx-Konfiguration mit `allow`/`deny` |
| `03_nginx_aktiv.log` | `nginx -t`, Dienstzustand, Auszug aus `nginx -T` |
| `04_listener.log` | Nginx im LAN, die Anwendungen weiterhin auf `127.0.0.1` |
| `05_test_ubuntu.log` | Zugriff lokal und ueber die LAN-Adresse, mit Inhalt |
| `06_zugriffslog.log` | Nginx-Zugriffsprotokoll, 200 und 403 nebeneinander |
| `07_portkette.log` | die Kette und die Begruendung der Loopback-Bindung |
| `08_offene_punkte.log` | was von Hand fehlt, plus die bekannte Abweichung |

Der Unterbefehl ist wiederholbar: ein zweiter Aufruf mit denselben Angaben
erzeugt dieselbe Konfiguration.

### Negativtest

Dass `deny all` wirkt, zeigt nur ein Zugriff von einer nicht freigegebenen
Adresse. Dazu wird die Freigabe kurz auf eine Adresse aus TEST-NET-3
(`203.0.113.1`, laut RFC 5737 nie in Betrieb) umgestellt, der Kali ist also
ausgesperrt:

```bash
UBUNTU_IP='192.168.110.61' KALI_IP='192.168.110.xx' ./scripts/belege.sh freigabe-negativ
```

Das Skript haelt an und wartet. Jetzt auf dem **Kali**:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  --connect-timeout 5 --max-time 10 http://192.168.110.61:8082/
```

Erwartet wird **HTTP 403**. Die Zahl traegst du in `10_negativtest.log` ein.
Danach Enter druecken, die echte Freigabe wird automatisch wiederhergestellt
(`11_wiederherstellung.log`). Auch bei Strg-C laeuft die Wiederherstellung.

### Drei Dinge von Hand

Das steht so auch in `08_offene_punkte.log`:

1. **Zugriff vom Kali.** Auf dem Kali ausfuehren, die Datei per `scp` nach
   `belege/12_freigabe_nginx/08_test_kali.log` legen.
2. **Bildschirmaufnahmen** vom Browser auf dem Kali, mit sichtbarer URL
   `http://<ubuntu-ip>:8082` und `:8083`, als `09_browser_kali_*.png`.
3. **Negativtest** wie oben, HTTP 403 eingetragen.

Zum Schluss das Inhaltsverzeichnis neu schreiben und committen:

```bash
./scripts/belege.sh index
cd .. && git add belege EXPOSE.md && git commit -m 'Belege Netzfreigabe' && git push
```

### Fuer die Abgabevorlage

Festhalten: tatsaechliche Ubuntu-IP, die vollstaendige Browser-URL, den
SSH-Befehl mit dem vereinbarten Konto und die Portkette

```
Browser auf Kali --> Nginx <ubuntu-ip>:<port> --> 127.0.0.1:<port> --> Container:8000 --> app.py
```
