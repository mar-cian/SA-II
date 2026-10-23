# Leistungsbeurteilung 1 Abgabe

Name: Gian-Marco Rieder
Projekt: Karate Robot mit Betriebsanzeige (Local AI, Modul SAII)

> Vorbereiteter Stand. Alles, was mit **[messen]** markiert ist, wird erst
> waehrend der Durchfuehrung eingetragen. Nicht ausgefuehrte Tests bleiben als
> "nicht durchgefuehrt" stehen.

## 1 Zugriff und Architektur

| Angabe | Tatsächlicher Wert |
| --- | --- |
| Hostname und IP von vmls1 | `vmls1`, 192.168.110.61 **[messen]** mit `hostname -f; ip -br -4 address` bestaetigen |
| Vollständige Browser-URL | `http://192.168.110.61:8084/` |
| SSH-Befehl und Benutzerkonto | `ssh vmadmin@192.168.110.61`, Konto `vmadmin`, Port 22. Zugangsdaten separat. |
| Absoluter Projektpfad | `/home/vmadmin/workspace/AI-Docker-Lab/04_Karate` |
| Hostport und Containerport | Host `127.0.0.1:8084`, Container `8000` |

Der Hostport ist bewusst nur auf das Loopback gebunden. Ins Netz freigegeben
wird er von Nginx, nicht von Docker.

```
Kali, Firefox  192.168.110.70
      |  HTTP GET /  und  GET /api/info
      v
Nginx          192.168.110.61:8084        allow 192.168.110.70; deny all
      |  proxy_pass http://127.0.0.1:8084
      v
Host-Loopback  127.0.0.1:8084             docker-proxy
      |
      v
Container      karate:8000                app.py, hoert auf 0.0.0.0
```

**Wo was laeuft.** Die Animation laeuft ausschliesslich im Browser: CSS-Keyframes
und ein kleines Skript, kein Serveranteil. Die Statusabfrage dagegen geht alle
5 Sekunden ueber die ganze Kette oben bis zu `/api/info` im Container. Darum
bewegt sich der Roboter weiter, wenn der Server ausfaellt, und nur das
Dashboard meldet den Ausfall.

Zwei verschiedene Grenzen, die nicht verwechselt werden duerfen: im Container
hoert die Anwendung auf `0.0.0.0`, weil `docker-proxy` sie sonst nicht
erreichen wuerde. Die Begrenzung auf lokalen Zugriff kommt aus der
Veroeffentlichung `127.0.0.1:8084:8000` in der `compose.yaml`, die Begrenzung
auf den Kali aus der `allow`/`deny`-Liste in Nginx.

## 2 How-to und Verständnis der Handlungen

Alle Befehle aus `/home/vmadmin/workspace/AI-Docker-Lab/04_Karate`.

### H1 Image bauen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose build
sudo docker images karate-robot
```
Zweck, Veränderung und unveränderter Zustand: Baut aus `Dockerfile` und
`app.py` ein neues Image. Neu ist die Image-ID. Unveraendert bleiben der
laufende Container, die `compose.yaml` und die anderen Umgebungen auf dieser
VM, weil der Build nur ein Image erzeugt und nichts austauscht.
Test/Beleg: T5, Image-ID vorher und nachher.

### H2 Container starten

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose up -d
sudo docker compose ps
```
Zweck, Veränderung und unveränderter Zustand: Erstellt aus dem vorhandenen
Image einen Container und veroeffentlicht `127.0.0.1:8084`. Neu sind
Container-ID, Laufzeit und Anfragezaehler. Unveraendert bleiben Image,
Nginx-Konfiguration und der Quellstand.
Test/Beleg: T2, T7.

### H3 Container dem bereitgestellten Zugangsport zuordnen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
grep ports: compose.yaml                 # 127.0.0.1:8084:8000
sudo docker compose up -d
curl -sS -o /dev/null -w 'lokal    HTTP %{http_code}\n' http://127.0.0.1:8084/
curl -sS -o /dev/null -w 'ueber LAN HTTP %{http_code}\n' http://192.168.110.61:8084/
```
Zweck, Veränderung und unveränderter Zustand: Ordnet den Containerport 8000 dem
bereitgestellten Hostport 8084 zu. Veraendert wird nur die Veroeffentlichung,
nicht die Anwendung: im Container hoert sie unveraendert auf Port 8000. Die
Freigabe ins Netz leistet Nginx und ist bereitgestellte Infrastruktur.
Test/Beleg: T7. Die beiden `curl`-Aufrufe trennen die Verantwortung: 200 lokal
und kein 200 ueber die LAN-Adresse heisst, die Zuordnung stimmt und die
Freigabe fehlt.

### H4 Status und Logs prüfen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose ps
sudo docker compose logs --tail 30 app
sudo docker inspect --format 'Health={{.State.Health.Status}} Running={{.State.Running}} RestartCount={{.RestartCount}}' \
  "$(sudo docker compose ps -q app)"
```
Zweck, Veränderung und unveränderter Zustand: Trennt Prozesszustand und
Health-Status. Veraendert nichts, es wird nur gelesen.
Test/Beleg: T2, T6. `Running=true` allein ist kein Nachweis fuer eine
funktionierende Anwendung, deshalb der Health-Status daneben.

### H5 Stoppen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose stop
```
Zweck, Veränderung und unveränderter Zustand: Beendet den Prozess, der
Container bleibt bestehen. Neu ist der Zustand `exited`. Unveraendert bleiben
Container-ID, Image und Nginx-Konfiguration. Die Restart Policy greift hier
bewusst nicht: `unless-stopped` behandelt einen absichtlichen Stopp nicht als
Absturz.
Test/Beleg: T3.

### H6 Neustarten

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose start        # nach stop
sudo docker compose restart app  # im laufenden Betrieb
```
Zweck, Veränderung und unveränderter Zustand: Startet den Prozess im selben
Container aus demselben Image neu. Neu sind Laufzeit und Anfragezaehler.
Unveraendert bleiben Container-ID, Image-ID und `RestartCount`. Eine
Codeaenderung wird dabei **nicht** wirksam.
Test/Beleg: T4, R2.

### H7 Container entfernen und neu erstellen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose ps -q app        # Container-ID vorher
sudo docker compose down
sudo docker compose up -d --build
sudo docker compose ps -q app        # Container-ID nachher
```
Zweck, Veränderung und unveränderter Zustand: Entfernt Container und Netz und
erstellt beides neu, mit `--build` zusaetzlich aus einem neu gebauten Image.
Neu sind Image-ID und Container-ID, `RestartCount` beginnt wieder bei 0.
Unveraendert bleiben `compose.yaml`, Hostport und Nginx-Konfiguration, deshalb
gilt dieselbe URL weiter.
Test/Beleg: T5, R2.

### H8 Benutzer und read-only Einstellung prüfen

Befehl mit Arbeitsverzeichnis:
```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sudo docker compose exec app id
sudo docker compose exec app touch /beweis          # muss scheitern
sudo docker compose exec app touch /tmp/beweis      # muss gelingen
sudo docker inspect --format 'User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Policy={{.HostConfig.RestartPolicy.Name}}' \
  "$(sudo docker compose ps -q app)"
```
Zweck, Veränderung und unveränderter Zustand: Belegt, dass der Prozess als UID
10001 laeuft und das Root-Dateisystem nicht beschreibbar ist. Veraendert wird
nur `/tmp/beweis`, und das liegt in einem tmpfs und verschwindet mit dem
Container.
Test/Beleg: T6.

## 3 Verständnis der Komponenten

| ID | Komponente | Aufgabe, Zusammenarbeit und Auswirkung eines Ausfalls | Stelle im eigenen Projekt |
| --- | --- | --- | --- |
| K1 | Browser/Animation | Rechnet die Animation und fragt den Status ab. Faellt er aus, ist nichts sichtbar, der Server laeuft weiter. | `SCRIPT` und die Keyframes `schlag`/`tritt` in `app.py` |
| K2 | Backend/Webserver | Liefert Seite und JSON. Faellt er aus, laeuft die Animation weiter, das Dashboard meldet "nicht erreichbar". | `Handler.do_GET` und `ThreadingHTTPServer` in `app.py` |
| K3 | Dashboard/Status-API | `/api/info` liefert `application`, `status`, `time`, `uptime_seconds`; die Seite fragt alle 5 s. Faellt sie aus, veralten die Werte und werden gekennzeichnet. | `/api/info` in `do_GET`, `pruefen()` und `zeichneStatus()` |
| K4 | Dockerfile/Image | Legt Grundlage, Code und Benutzer fest. Ein falsch gebautes Image startet nicht oder enthaelt alten Code. | `Dockerfile`, Zeilen `COPY app.py` und `USER 10001:10001` |
| K5 | Compose/Container | Legt Projektname, Portveroeffentlichung, Rechte und Restart Policy fest. Fehlt sie, ist der Container nicht erreichbar. | `compose.yaml` |
| K6 | Healthcheck | Fragt `/health` alle 5 s. Er sagt nur, ob die Anwendung antwortet, nicht ob sie richtig rechnet. Schlaegt er fehl, gilt der Container als `unhealthy` und laeuft trotzdem weiter. | `healthcheck:` in `compose.yaml` |
| K7 | Ports/Nginx | Bildet die Kette LAN-Adresse zu Loopback zu Containerport. Faellt Nginx aus, bleibt die App lokal erreichbar, vom Kali nicht. | `ports:` in `compose.yaml` und `/etc/nginx/conf.d/lb1-8084.conf` |

## 4 Testprotokoll

| ID | Soll | Handlung | Tatsächliches Ist und Zeitpunkt | Beleg | Schlussfolgerung |
| --- | --- | --- | --- | --- | --- |
| T1 | Zwei Übungen; Start, Pause und Auswahl funktionieren | Im Browser auf dem Kali: Start, Umschalten auf Tritt, Pause, erneut Start | **[messen]** | S01, Live-Vorfuehrung | **[messen]** |
| T2 | Laufzeit steigt; Prüfzeitpunkt aktualisiert | H4, dazu `/api/info` zweimal im Abstand von 10 s | **[messen]** | S02, Terminalwerte unten | **[messen]** |
| T3 | Ausfall nach etwa 15 Sekunden; alte Werte gekennzeichnet | H5 bei offener Seite auf dem Kali | **[messen]** | S03 | **[messen]** |
| T4 | Wieder erreichbar; Laufzeit beginnt neu | H2 bzw. H6, Seite weiterhin offen | **[messen]** | S03 | **[messen]** |
| T5 | Neue Container-ID; App funktioniert | H7 | **[messen]** | Terminalwerte unten | **[messen]** |
| T6 | Non-root und read-only bestätigt | H8 | **[messen]** | S04, Terminalwerte unten | **[messen]** |
| T7 | URL auf zweitem zugelassenen Rechner öffnen | `http://192.168.110.61:8084/` im Firefox auf dem Kali (192.168.110.70) | **[messen]** | S01 | **[messen]** |

Terminalwerte vorher und nachher: **[messen]**, werden vom Sammelskript nach
`belege/lb1/` geschrieben, siehe Abschnitt 7.

Der Ausfall in T3 wird spaetestens nach einem Abfrageintervall erkannt. Bei
gestopptem Server lehnt das Betriebssystem die Verbindung sofort ab, also nach
hoechstens 5 s. Haengt der Server, kommt das Zeitlimit von 5 s dazu, zusammen
10 s. Beides liegt unter den geforderten etwa 15 s.

## 5 Belege

| S-ID | Handlung | Aussage des Bildes |
| --- | --- | --- |
| S01 | Browser auf dem Kali, URL sichtbar, Roboter in Bewegung, Uebung Tritt gewaehlt | Deckt T1 und T7: App vom zweiten Rechner erreichbar, Bedienung funktioniert |
| S02 | Dieselbe Seite, Dashboard mit Laufzeit und Pruefzeitpunkt, daneben das Terminal mit zwei `/api/info`-Aufrufen | Deckt T2: Serverdaten werden wirklich aktualisiert |
| S03 | Seite nach `docker compose stop`, "nicht erreichbar", Werte durchgestrichen, Hinweis mit Uhrzeit der letzten Antwort | Deckt T3 und, nach dem Wiederstart, T4 |
| S04 | Terminal mit `id`, dem gescheiterten `touch /beweis` und `docker inspect` | Deckt T6: non-root und read-only |

Relative Pfade, zum Beispiel `![S01 Roboter vom Kali](screenshots/S01_kali_roboter.png)`.
Die Animation wird zusaetzlich live vorgefuehrt, weil ein Einzelbild keine
Bewegung beweist.

## 6 Reflexion

### R1 Browser und Serverausfall

Die Animation besteht aus CSS-Keyframes, die der Browser selbst rechnet; vom
Server kommt dafuer nichts. Nur das Dashboard braucht den Server, es fragt alle
5 Sekunden `/api/info` ab. Faellt der Server aus, laeuft die Bewegung also
unveraendert weiter. Erkannt wird der Ausfall an der fehlgeschlagenen Abfrage,
nicht an einer Meldung des Servers: schon der erste Fehlversuch setzt die
Anzeige auf "nicht erreichbar". Dabei bleiben "Letzte Pruefung" und die
Serverwerte bewusst getrennt. Der Pruefzeitpunkt wird bei jedem Versuch neu
gesetzt, auch beim gescheiterten, die Serverwerte bleiben auf dem letzten
Erfolg stehen und werden als veraltet gekennzeichnet. Ein Zeitstempel, der
weiterlaeuft, waehrend die Werte alt sind, ist genau der Unterschied zwischen
geprueft und gueltig. Bezug K1 bis K3 und T3.

### R2 Codeänderung

Der Code liegt per `COPY app.py` im Image. Nach einer Aenderung ist deshalb
`sudo docker compose up -d --build` noetig, also H1 und H7 zusammen.
`restart` genuegt nicht, weil es denselben Prozess aus demselben Image neu
startet, und dieses Image enthaelt den alten Stand. Der Container hat keine
Verbindung zur Quelldatei auf dem Host; die bestuende nur bei einem Bind Mount,
den dieses Projekt bewusst nicht hat.

Dafuer gibt es in diesem Projekt einen echten Beleg und keinen konstruierten:
In Auftrag 3 war der Endpunkt `/api/info` im Quellcode vorhanden, nach einem
`git pull` mit anschliessendem `docker compose up -d` ohne `--build` antwortete
die laufende Anwendung aber weiter mit HTTP 404 und nannte nur drei gueltige
Routen. Weil das Tag `service-clock:1.0.0` bereits existierte, hat Docker das
alte Image weiterverwendet. Erst `up -d --build` hat es behoben. Festgehalten
in `belege/12_freigabe_nginx/05_test_ubuntu.log`. Bezug H1, H6 und H7.

### R3 Qwen-Vorschlag prüfen

**[messen]** Hier gehoert ein Austausch aus dieser Pruefung hinein, mit drei
Teilen: der konkrete Vorschlag von Qwen, wie ich ihn geprueft habe mit Nennung
der Code- oder Konfigurationsstelle und des Tests, und meine Entscheidung,
uebernommen oder korrigiert. Prompt und Antwort werden unter
`belege/lb1/qwen/` abgelegt. Ein bestaetigter Vorschlag genuegt, ein Fehler
wird nicht erfunden.

## 7 Dateien Quellen und offene Punkte

**Projektdateien** unter `04_Karate/`:

| Datei | Inhalt |
| --- | --- |
| `app.py` | Anwendung, nur Standardbibliothek: Seite, Animation, `/api/info`, `/health` |
| `Dockerfile` | Image, nicht privilegierter Benutzer 10001 |
| `compose.yaml` | Projektname, Portveroeffentlichung, Rechte, Healthcheck, Restart Policy |
| `.dockerignore` | haelt Test- und Dokumentationsdateien aus dem Image |
| `scripts/belege-lb1.sh` | sammelt die Terminalbelege zu T2, T5 und T6 |
| `screenshots/` | S01 bis S04 |
| `README.md` | diese Abgabe |

Ausserhalb des Projektordners, weil es den Host betrifft:
`/etc/nginx/conf.d/lb1-8084.conf`, als Kopie unter `belege/lb1/` abgelegt.

**Fachquellen**

- Arbeitsblatt 4, Kapitel 3 bis 5, und das Unterrichtspaket `expose-lab.sh`
- Docker-Dokumentation zu Compose, Restart Policy und Healthcheck
- Nginx-Dokumentation zu `listen`, `allow`/`deny` und `proxy_pass`
- MDN zu `AbortController` und `fetch`
- Qwen 3 lokal ueber Ollama, Protokoll unter `belege/lb1/qwen/`

**Nicht erfüllte Anforderungen oder verbleibende Fehler**

- **[messen]** nach der Durchfuehrung ehrlich eintragen.
- Bekannt und bewusst: Die Anwendung hat keine Authentifizierung. Wer den Port
  erreicht, sieht Name, Laufzeit und Pruefzeitpunkt. Begrenzt wird der Zugriff
  durch die Bindung auf `127.0.0.1` und die `allow`/`deny`-Liste in Nginx.
- Bereitgestellte Infrastruktur, also `expose-lab.sh` und die Freigabe des
  Pruefungsports, ist verwendet und erklaert, aber nicht selbst entwickelt.
