# Leistungsbeurteilung 1 Abgabe

Name: Gian-Marco Rieder
Projekt: Karate Robot mit Betriebsanzeige (Local AI, Modul SAII)

`[messen]` wird waehrend der Durchfuehrung eingetragen.

## 1 Zugriff und Architektur

| Angabe | Tatsächlicher Wert |
| --- | --- |
| Hostname und IP von vmls1 | `li264-vmLS1`, 192.168.110.61 |
| Vollständige Browser-URL | `http://192.168.110.61:8084/` |
| SSH-Befehl und Benutzerkonto | `ssh vmadmin@192.168.110.61`, Konto `vmadmin`, Port 22. Zugangsdaten separat. |
| Absoluter Projektpfad | `/home/vmadmin/workspace/AI-Docker-Lab/04_Karate` |
| Hostport und Containerport | Host `127.0.0.1:8084`, Container `8000` |

```
Kali, Firefox  192.168.110.70        <- Animation laeuft hier
      |  GET /  und alle 5 s GET /api/info
      v
Nginx          192.168.110.61:8084   allow 192.168.110.70; deny all
      |  proxy_pass http://127.0.0.1:8084
      v
Host-Loopback  127.0.0.1:8084        docker-proxy
      |
      v
Container      8000                  app.py, hoert auf 0.0.0.0
```

Die Animation laeuft im Browser, ohne Serveranteil. Nur die Statusabfrage geht
ueber die ganze Kette bis `/api/info`.

Zwei Grenzen: `127.0.0.1:8084:8000` in der `compose.yaml` begrenzt auf lokalen
Zugriff, die `allow`/`deny`-Liste in Nginx auf den Kali. Im Container hoert die
Anwendung auf `0.0.0.0`, sonst erreicht `docker-proxy` sie nicht.

## 2 How-to und Verständnis der Handlungen

Alle Befehle aus `/home/vmadmin/workspace/AI-Docker-Lab/04_Karate`.

### H1 Image bauen

```bash
sudo docker compose build && sudo docker images karate-robot
```
Baut aus `Dockerfile` und `app.py` ein neues Image. Neu: Image-ID. Unveraendert:
laufender Container, `compose.yaml`. Beleg: T5.

### H2 Container starten

```bash
sudo docker compose up -d && sudo docker compose ps
```
Erstellt den Container aus dem Image und veroeffentlicht `127.0.0.1:8084`. Neu:
Container-ID, Laufzeit. Unveraendert: Image, Nginx. Beleg: T2, T7.

### H3 Zugangsport zuordnen

```bash
grep ports: compose.yaml
curl -sS -o /dev/null -w 'lokal     HTTP %{http_code}\n' http://127.0.0.1:8084/
curl -sS -o /dev/null -w 'ueber LAN HTTP %{http_code}\n' http://192.168.110.61:8084/
```
Ordnet Containerport 8000 dem Hostport 8084 zu. Veraendert nur die
Veroeffentlichung, nicht die Anwendung. Die Netzfreigabe leistet Nginx.
Beleg: T7. 200 lokal ohne 200 ueber LAN hiesse: Zuordnung stimmt, Freigabe fehlt.

### H4 Status und Logs prüfen

```bash
sudo docker compose ps
sudo docker compose logs --tail 30 app
sudo docker inspect --format 'Health={{.State.Health.Status}} Running={{.State.Running}} RestartCount={{.RestartCount}}' \
  "$(sudo docker compose ps -q app)"
```
Trennt Prozesszustand und Health. Veraendert nichts. `Running=true` allein ist
kein Nachweis fuer eine funktionierende Anwendung. Beleg: T2, T6.

### H5 Stoppen

```bash
sudo docker compose stop
```
Beendet den Prozess, Container bleibt bestehen. Neu: Zustand `exited`.
Unveraendert: Container-ID, Image. `unless-stopped` behandelt einen bewussten
Stopp nicht als Absturz, die Policy greift also nicht. Beleg: T3.

### H6 Neustarten

```bash
sudo docker compose start          # nach stop
sudo docker compose restart app    # im laufenden Betrieb
```
Startet den Prozess im selben Container aus demselben Image. Neu: Laufzeit.
Unveraendert: Container-ID, Image-ID, `RestartCount`. Eine Codeaenderung wird
dabei **nicht** wirksam. Beleg: T4, R2.

### H7 Container entfernen und neu erstellen

```bash
sudo docker compose ps -q app      # ID vorher
sudo docker compose down
sudo docker compose up -d --build
sudo docker compose ps -q app      # ID nachher
```
Entfernt Container und Netz und erstellt beides neu. Neu: Image-ID,
Container-ID, `RestartCount` wieder 0. Unveraendert: `compose.yaml`, Hostport,
Nginx, also gilt dieselbe URL. Beleg: T5, R2.

### H8 Benutzer und read-only prüfen

```bash
sudo docker compose exec app id
sudo docker compose exec app touch /beweis       # muss scheitern
sudo docker compose exec app touch /tmp/beweis   # muss gelingen
sudo docker inspect --format 'User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Policy={{.HostConfig.RestartPolicy.Name}}' \
  "$(sudo docker compose ps -q app)"
```
Belegt UID 10001 und ein nicht beschreibbares Root-Dateisystem. Veraendert nur
`/tmp/beweis` im tmpfs. Beleg: T6.

## 3 Verständnis der Komponenten

| ID | Komponente | Aufgabe, Zusammenarbeit und Auswirkung eines Ausfalls | Stelle im eigenen Projekt |
| --- | --- | --- | --- |
| K1 | Browser/Animation | Rechnet die Animation, fragt den Status ab. Faellt er aus: nichts sichtbar, Server laeuft weiter. | `SCRIPT` und Keyframes `schlag`/`tritt` in `app.py` |
| K2 | Backend/Webserver | Liefert Seite und JSON. Faellt er aus: Animation laeuft weiter, Dashboard meldet "nicht erreichbar". | `Handler.do_GET` in `app.py` |
| K3 | Dashboard/Status-API | `/api/info` liefert `application`, `status`, `time`, `uptime_seconds`, Abfrage alle 5 s. Faellt sie aus: Werte veralten und werden gekennzeichnet. | `/api/info`, `pruefen()`, `zeichneStatus()` |
| K4 | Dockerfile/Image | Legt Grundlage, Code und Benutzer fest. Falsch gebaut: alter Code im Container. | `COPY app.py`, `USER 10001:10001` |
| K5 | Compose/Container | Projektname, Portveroeffentlichung, Rechte, Restart Policy. Fehlt sie: nicht erreichbar. | `compose.yaml` |
| K6 | Healthcheck | Fragt `/health` alle 5 s. Sagt nur, ob die Anwendung antwortet, nicht ob sie richtig rechnet. Schlaegt er fehl: `unhealthy`, laeuft aber weiter. | `healthcheck:` in `compose.yaml` |
| K7 | Ports/Nginx | LAN-Adresse zu Loopback zu Containerport. Faellt Nginx aus: lokal erreichbar, vom Kali nicht. | `ports:` und `/etc/nginx/conf.d/lb1-8084.conf` |

## 4 Testprotokoll

| ID | Soll | Handlung | Tatsächliches Ist und Zeitpunkt | Beleg | Schlussfolgerung |
| --- | --- | --- | --- | --- | --- |
| T1 | Zwei Übungen; Start, Pause und Auswahl funktionieren | Browser auf dem Kali: Start, Tritt, Pause, Start | `[messen]` | S01, Live | Soll erfüllt. Zwei unterscheidbare Übungen, Bedienung ohne Neuladen. |
| T2 | Laufzeit steigt; Prüfzeitpunkt aktualisiert | H4, `/api/info` zweimal im Abstand | `[messen]` | S02 | Soll erfüllt. Die Anzeige zeigt echte Serverdaten, keine festen Werte. |
| T3 | Ausfall nach etwa 15 Sekunden; alte Werte gekennzeichnet | H5 bei offener Seite | `[messen]` | S03 | Soll erfüllt. Ausfall innerhalb eines Abfrageintervalls erkannt, alte Werte gekennzeichnet. |
| T4 | Wieder erreichbar; Laufzeit beginnt neu | H6, Seite weiterhin offen | `[messen]` | S04 | Soll erfüllt. Wiederanlauf ohne Neuladen erkannt, die Laufzeit gehört zum Prozess. |
| T5 | Neue Container-ID; App funktioniert | H7 | `[messen]` | S05 | Soll erfüllt. `down` entfernt den Container wirklich, `up` erstellt einen neuen aus dem Image. |
| T6 | Non-root und read-only bestätigt | H8 | `[messen]` | S05 | Soll erfüllt. Kein root, Root-Dateisystem nicht beschreibbar, nur `/tmp` als tmpfs. |
| T7 | URL auf zweitem zugelassenen Rechner öffnen | `http://192.168.110.61:8084/` auf dem Kali | `[messen]` | S01 | Soll erfüllt. Zugriff vom zweiten Rechner über Nginx, die Anwendung bleibt auf Loopback gebunden. |

Werte zu den Bildern, aus einem Screenshot nicht kopierbar:

```
T2  uptime_seconds  erste Abfrage [messen]   zweite Abfrage [messen]
T3  gestoppt um [messen]   "nicht erreichbar" um [messen]   Differenz [messen] s
T4  gestartet um [messen]  wieder erreichbar um [messen]    neue Laufzeit [messen] s
T5  Container-ID  vorher [messen]  nachher [messen]
T5  Image-ID      vorher [messen]  nachher [messen]
T5  waehrend des Abbaus: HTTP 000
T6  id [messen]   touch /beweis [messen]   inspect [messen]
```

Erkennungszeit in T3: bei gestopptem Server lehnt das Betriebssystem die
Verbindung sofort ab, also hoechstens ein Intervall, 5 s. Haengt der Server,
kommen 5 s Zeitlimit dazu, zusammen 10 s. Beides unter den geforderten 15 s.

## 5 Belege

### S01 Roboter und Dashboard vom Kali

Deckt **T1** und **T7**.

Roboter via Kali (Ports exposed)

![alt text](image-1.png)

### S02 Zwei Abfragen von /api/info im Abstand

Deckt **T2**.

Servicecloack updates

![alt text](image-2.png) ![alt text](image-3.png)

### S03 Ausfall erkannt, alte Werte gekennzeichnet

Deckt **T3**.

Vor dem stoppen:

![alt text](image-5.png)

Nach dem stoppen:

![alt text](image-7.png)

### S04 Wiederanlauf, Laufzeit beginnt neu

Deckt **T4**.

Wieder online:

![alt text](image-8.png)

### S05 Container-IDs, Benutzer und read-only

Deckt **T5** und **T6**.

Neue Container-ID:

![alt text](image-9.png)

Nach rebuild:

![alt text](image-10.png)

Die Animation wird zusaetzlich live vorgefuehrt, weil ein Einzelbild keine
Bewegung beweist.

## 6 Reflexion

### R1 Browser und Serverausfall

Die Animation sind CSS-Keyframes, die der Browser selbst rechnet. Vom Server
kommt dafuer nichts, nur das Dashboard fragt ihn alle 5 s ueber `/api/info`.
Darum laeuft die Bewegung beim Ausfall unveraendert weiter. Erkannt wird der
Ausfall an der gescheiterten Abfrage, nicht an einer Meldung des Servers: schon
der erste Fehlversuch setzt die Anzeige auf "nicht erreichbar". Pruefzeitpunkt
und Serverwerte bleiben getrennt. Der Pruefzeitpunkt wird bei jedem Versuch neu
gesetzt, auch beim gescheiterten, die Serverwerte bleiben auf dem letzten Erfolg
stehen und werden als veraltet gekennzeichnet. Bezug K1 bis K3, T3.

### R2 Codeänderung

Der Code liegt per `COPY app.py` im Image, also ist nach einer Aenderung
`up -d --build` noetig, H1 und H7 zusammen. `restart` genuegt nicht, weil es
denselben Prozess aus demselben Image startet, und dieses Image enthaelt den
alten Stand. Eine Verbindung zur Quelldatei auf dem Host bestuende nur bei einem
Bind Mount, den dieses Projekt nicht hat.

Belegt erlebt: In Auftrag 3 war `/api/info` im Quellcode vorhanden, nach
`git pull` und `up -d` ohne `--build` antwortete die Anwendung weiter mit
HTTP 404. Das Tag `service-clock:1.0.0` existierte bereits, deshalb hat Docker
das alte Image weiterverwendet. Erst `up -d --build` hat es behoben. Festgehalten
in `belege/12_freigabe_nginx/05_test_ubuntu.log`. Bezug H1, H6, H7.

### R3 Qwen-Vorschlag prüfen

`[messen]` Vorschlag, eigene Pruefung mit Code- oder Konfigurationsstelle und
Test, Entscheidung. Prompt und Antwort unter `belege/lb1/qwen/`.

## 7 Dateien Quellen und offene Punkte

**Projektdateien** unter `04_Karate/`: `app.py`, `Dockerfile`, `compose.yaml`,
`.dockerignore`, `scripts/`, `screenshots/`, `README.md`. Ausserhalb, weil es
den Host betrifft: `/etc/nginx/conf.d/lb1-8084.conf`, Kopie unter `belege/lb1/`.

**Fachquellen**: Arbeitsblatt 4 Kapitel 3 bis 5 und `expose-lab.sh`;
Docker-Dokumentation zu Compose, Restart Policy und Healthcheck;
Nginx-Dokumentation zu `listen`, `allow`/`deny` und `proxy_pass`; MDN zu
`AbortController` und `fetch`; Qwen 3 lokal ueber Ollama.

**Nicht erfüllte Anforderungen oder verbleibende Fehler**

- `[messen]`
- Keine Authentifizierung. Wer den Port erreicht, sieht Name, Laufzeit und
  Pruefzeitpunkt. Begrenzt durch die Bindung auf `127.0.0.1` und die
  `allow`/`deny`-Liste in Nginx.
- `expose-lab.sh` und die Freigabe des Pruefungsports sind bereitgestellte
  Infrastruktur, verwendet und erklaert, nicht selbst entwickelt.
