# Phase F: Security, Architekturentscheidung

Sechs Fragen aus dem Aufgabenblatt. Zu jeder stehen hier die **Befunde aus
deiner Loesung** mit Fundstelle und Beleg. Die **Antwort** schreibst du selbst,
in deinen Worten: das ist der Teil, den du in der Abnahme verteidigst.

Belege dazu erzeugen:

```bash
cd ~/workspace/AI-Docker-Lab/02_Monitoring
./scripts/belege.sh phase-f
```

Die Dateien landen unter `belege/10_phaseF_security/`.

---

## 1. Wer kann den Docker-Daemon ansprechen? Welche Hostrechte entstehen daraus?

**Befund**

Der Daemon haengt an `/var/run/docker.sock`, Eigentuemer `root`, Gruppe
`docker`, Rechte `0660`. Ansprechen kann ihn damit `root` und jedes Mitglied der
Gruppe `docker`.

In deiner Loesung:

| Komponente | Zugang zum Socket |
|---|---|
| Host-Collector | ja, laeuft als `root` unter systemd |
| AI-Relay | nein, `DynamicUser`, nur IP-Sockets erlaubt |
| Dashboard-Container | nein, der Socket ist nicht eingehaengt |
| Laborcontainer | nein |

Wer die API erreicht, kann einen Container mit beliebigem Hostmount und
`--privileged` starten. Damit ist das gesamte Dateisystem lesbar und als `root`
beschreibbar. Mitgliedschaft in der Gruppe `docker` ist deshalb praktisch
gleichbedeutend mit `root`, ohne dass ein Passwort oder `sudo` noetig waere.

Beleg: `f1_docker_zugriff.log`

**Deine Antwort:**



---

## 2. Warum macht ein `:ro`-Mount des Docker-Sockets dessen API nicht read-only?

**Befund**

`:ro` wirkt auf den Dateiknoten im Mount-Namespace des Containers. Es
verhindert, dass der Container die Socketdatei ersetzt, loescht oder ihre Rechte
aendert. Es filtert keine einzige Anfrage, die durch den Socket laeuft.

Der Socket ist nur der Transport. Darueber laeuft eine HTTP-API mit `GET`,
`POST`, `PUT` und `DELETE`. Der Kernel kennt keine lesenden und schreibenden
Sockets, er kennt nur Bytes in beide Richtungen.

Der Beleg zeigt das direkt: `POST /containers/create` wird von der API
angenommen. Der Fehlercode kommt vom unvollstaendigen Rumpf, nicht von einer
Ablehnung der Methode. Die Route ist erreichbar.

Folge fuer die Absicherung des Containers: `read_only: true`,
`cap_drop: [ALL]`, `no-new-privileges` und die UID 10001 waeren bei
eingehaengtem Socket praktisch wirkungslos, weil der Weg nach draussen nicht
durch den Container fuehrt, sondern durch den Daemon.

Beleg: `f2_socket_akzeptiert_schreibend.log`

**Deine Antwort:**



---

## 3. Welche API-Routen und HTTP-Methoden muesste ein Proxy zulassen oder sperren? Warum koennen auch lesende Abfragen sensible Daten verraten?

**Befund**

Fuer die Ueberwachung genuegen wenige lesende Routen:

| Erlauben | Zweck |
|---|---|
| `GET /_ping`, `GET /version` | Erreichbarkeit |
| `GET /containers/json` | Liste der Container |
| `GET /containers/{id}/json` | Zustand, Health, Konfiguration |
| `GET /containers/{id}/logs` | Logzeilen |

Zu sperren waere alles Veraendernde, insbesondere:

| Sperren | Warum |
|---|---|
| `POST /containers/create`, `/start`, `/stop`, `/kill`, `/update` | Kontrolle ueber Container |
| `POST /containers/{id}/exec` | Codeausfuehrung in laufenden Containern |
| `POST /build`, `POST /images/create` | beliebigen Code ins System holen |
| `POST /volumes/create`, `/networks/create` | Hostpfade und Netze einhaengen |
| `DELETE` auf allem | Zerstoerung |

Auch die erlaubte Seite ist nicht harmlos. `GET /containers/{id}/json` liefert
`Config.Env` im Klartext. In echten Umgebungen stehen dort Passwoerter, Tokens
und Verbindungszeichenfolgen. `GET /containers/{id}/logs` liefert alles, was die
Anwendung ausgegeben hat, inklusive versehentlich protokollierter Geheimnisse.

Der Beleg zeigt das an deinen eigenen Containern: `API_URL` und `JOB_PATH`
stehen dort offen. Harmlos in diesem Labor, aber dasselbe Feld traegt in einer
echten Anwendung das Datenbankpasswort.

Ein Proxy muesste deshalb nicht nur nach Methode und Route filtern, sondern
Antwortinhalte beschneiden. Das ist aufwendig, muss gepflegt werden und wird
selbst zur kritischen Komponente.

Beleg: `f3_lesend_verraet_daten.log`

**Deine Antwort:**



---

## 4. Welche Rechte behaelt ein Host-Collector? Was schuetzt die Trennung, und was schuetzt sie nicht?

**Befund**

Ehrlich benannt: Der Collector laeuft als `root` und darf die Docker-API
ansprechen. Er bleibt damit root-aequivalent auf dem Host. Die Trennung
verschiebt dieses Recht, sie beseitigt es nicht.

Eingegrenzt wird er durch drei Dinge:

- **Allowlist im Code**: nur `ps`, `inspect`, `logs`, `version`. Jeder andere
  Unterbefehl wird vom Programm selbst abgelehnt.
- **systemd-Haertung**: `ProtectSystem=strict`, `ReadWritePaths` nur auf
  `/var/lib/hf-ops-collector`, `NoNewPrivileges`, `ProtectHome`,
  `RestrictAddressFamilies=AF_UNIX AF_NETLINK`, `MemoryMax`.
- **schmale Schnittstelle**: nach aussen gibt er genau eine JSON-Datei.

Was die Trennung schuetzt: die **Richtung** des Zugriffs. Code aus dem Container
erreicht die Docker-API nicht. Ein Fehler im Dashboard oder dessen Uebernahme
bleibt im Container, weil dort nichts liegt, womit man aus ihm herauskommt.

Was sie **nicht** schuetzt: Wer den Host uebernimmt oder diesen Dienst
kompromittiert, hat weiterhin die volle API. Die Allowlist ist eine
Selbstbeschraenkung des Programms, keine Durchsetzung durch den Kernel. Ein
Angreifer, der den Collector ersetzen kann, ersetzt auch die Allowlist.

Eine Variante ohne `root` waere ein eigener Benutzer in der Gruppe `docker`.
Die Gruppe ist aber ebenfalls root-aequivalent, der Gewinn waere kosmetisch.
Deshalb `root` plus Haertung statt Scheintrennung.

Belege: `f4_dashboard_ohne_socket.log`, `f5_haertung_collector.log`,
`f5_haertung_relay.log`

**Deine Antwort:**



---

## 5. Welche Nachteile hat Host-Netzwerk? Welche Dienste erreicht der Container zusaetzlich?

**Befund**

Mit `network_mode: host` entfaellt der eigene Netz-Namespace. Drei Folgen:

1. **`ports:` wirkt nicht mehr.** Der Prozess bindet direkt auf dem Host. Die
   bewusste Bindung auf `127.0.0.1:8082` waere damit Sache des Anwendungscodes,
   nicht mehr der Compose-Datei.
2. **Alles auf dem Loopback des Hosts wird erreichbar.** Genau darauf verlassen
   sich Dienste, die bewusst nur lokal gebunden sind.
3. **Portkonflikte und schlechtere Nachvollziehbarkeit**, weil mehrere
   Komponenten um dieselben Nummern konkurrieren.

Was der Container auf deinem Host zusaetzlich erreichen wuerde:

| Dienst | Port | heute erreichbar vom Container |
|---|---|---|
| Ollama | 127.0.0.1:8080 | nein |
| Open WebUI | 3000 | nein |
| Laborumgebung web | 127.0.0.1:8081 | nein |
| SSH | 22 | nein |
| alles weitere lokal Gebundene | | nein |

Mit Host-Netzwerk waere die ganze Spalte "ja". Die genaue Liste fuer deinen Host
steht im Beleg.

Deshalb wurde stattdessen das Relay gebaut: das Dashboard bleibt im Bridge-Netz
und erreicht genau eine Funktion statt eines ganzen Hosts.

Beleg: `f6_hostnetz_waere_erreichbar.log`

**Deine Antwort:**



---

## 6. Wie verhinderst du externe Freigaben, Geheimnisse in Logs, HTML-Ausfuehrung von Modelltext und automatische Modellaktionen?

**Befund, vier Teile**

**a) Externe Freigaben**

- Dashboard an `127.0.0.1:8082` gebunden. Die Variable `DASHBOARD_BIND` macht
  eine Oeffnung zu einem sichtbaren, dokumentierten Einzelschritt statt zu einer
  stillen Voreinstellung.
- Relay lauscht nur auf dem Gateway des Dashboard-Netzes (`172.31.240.1:8899`),
  vom LAN aus nicht sichtbar.
- Ollama bleibt unveraendert auf `127.0.0.1:8080`, es wurde nichts freigegeben.
- Zugriff von einem anderen Rechner laeuft ueber einen SSH-Tunnel,
  authentifiziert und verschluesselt, ohne die Bindung zu aendern.

Beleg: `f7_bindungen.log`

**b) Geheimnisse in Logs**

- Der Collector sendet an das Modell nur ausgewaehlte Felder: Name, Status,
  Prozesszustand, Health, Fehlerserie, Neustarts, Exit-Code, Ports und wenige
  gekuerzte Logzeilen. Environment-Variablen werden nicht mitgeschickt.
- Logzeilen werden von Steuer- und ANSI-Zeichen bereinigt und auf 200 Zeichen
  gekuerzt.
- Das Relay protokolliert Modell, Anfragegroesse und Dauer, nie Promptinhalte.
- Offene Grenze: Schreibt die beobachtete Anwendung selbst ein Geheimnis in ihr
  Log, landet es im Snapshot. Das ist benannt, nicht geloest.

Beleg: `f8_keine_geheimnisse_in_logs.log`

**c) HTML-Ausfuehrung von Modelltext**

- Jeder Fremdtext wird mit `html.escape` ausgegeben, Modelltext genauso wie
  Logzeilen. Nichts wird als Markup eingefuegt.
- Zusaetzlich eine Content-Security-Policy mit `default-src 'none'`,
  `base-uri 'none'`, `frame-ancestors 'none'`, dazu `X-Content-Type-Options`
  und `Referrer-Policy`.
- Geprueft mit einem `<script>`-Tag im Modelltext: er erscheint als sichtbarer
  Text, nicht als ausgefuehrtes Markup.

Beleg: `f9_modelltext_wird_escaped.log`

**d) Automatische Modellaktionen**

- Das Modell bekommt keine Werkzeuge. Es gibt keinen Pfad, auf dem seine
  Antwort einen Befehl ausloesen koennte.
- Die Antwort wird als Text in vier Abschnitte zerlegt und angezeigt. Sie wird
  nicht ausgewertet, nicht geparst zu Aktionen, nicht in Messwerte
  zurueckgeschrieben.
- Der Prompt sagt ausdruecklich, dass die Daten Daten sind und keine
  Anweisungen, und dass der naechste Schritt eine Pruefung durch einen Menschen
  ist.
- Die Analyse laeuft nur auf Knopfdruck, nicht automatisch im Hintergrund.
- Das Relay erzwingt zusaetzlich Modell-Allowlist, `stream: false`,
  Laengenlimit, Zeitlimit und eine Anfrage gleichzeitig.

**Deine Antwort:**



---

## Restrisiko, ehrlich benannt

Was diese Architektur **nicht** loest. Diese Liste gehoert in die Abgabe, weil
offene Einschraenkungen ehrlich zu benennen sind.

- Der Collector bleibt root-aequivalent. Die Trennung schuetzt die Richtung des
  Zugriffs, nicht den Host selbst.
- Die Allowlist im Collector ist eine Selbstbeschraenkung des Programms. Wer den
  Dienst ersetzen kann, ersetzt sie mit.
- Das Relay authentifiziert nicht. Es verlaesst sich darauf, dass nur Container
  im Netz `hf-ops-dashboard` seine Adresse erreichen. Ein weiterer Container in
  diesem Netz haette ebenfalls Zugang.
- Das Dashboard hat keine Authentifizierung. Wer den Port erreicht, sieht
  Containernamen, Images, Ports und Logzeilen. Deshalb die Bindung auf Loopback.
- Geheimnisse, die eine beobachtete Anwendung selbst in ihr Log schreibt,
  gelangen in den Snapshot und damit potenziell zum Modell.
- Die Modellantwort wird inhaltlich nicht geprueft. Begrenzt werden Form,
  Laenge und Dauer. Ob die Aussage stimmt, entscheidet der Mensch.

**Deine Ergaenzungen:**


