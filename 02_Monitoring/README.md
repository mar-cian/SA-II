# AI Operations Dashboard - Auftrag 2, Phase C

Eigene Ueberwachung der vorgegebenen Laborumgebung mit AI-Analyse. Drei Teile:

| Teil | Wo laeuft er | Aufgabe |
|---|---|---|
| `collector/` | Ubuntu-Host, systemd-Dienst | liest Docker nur lesend, schreibt `snapshot.json` |
| `dashboard/` | Container, Port 127.0.0.1:8090 | liest die Datei read-only, zeigt sie an, eigener `/health`, AI-Analyse |
| `ai-relay/` | Ubuntu-Host, systemd-Dienst | enger Zugang vom Dashboard-Netz zum lokal gebundenen Ollama |

Die Startumgebung in `01_Startumgebung` bleibt unveraendert.

```
docker.sock --> collector (Host, root) --> snapshot.json --[ro]--> |
                                                                   | dashboard
Ollama 127.0.0.1:8080 <-- ai-relay (Host, ohne Rechte) <----------- | (Container)
                                                                   |
                      ======== Vertrauensgrenze ===================|
```

Der Dashboard-Container hat keinen Docker-Zugriff: kein Socket, kein Proxy,
keine Hostrechte. Er liest eine Datei und fragt einen Endpunkt. Begruendung und
Variantenvergleich: `collector/README.md` Abschnitt 2 fuer den Docker-Zugriff,
`ai-relay/README.md` fuer die Netzwerkfrage.

## Reihenfolge beim Start

Alles auf der Ubuntu-VM, in `~/workspace/sa-ii`.

**1. Laborumgebung starten** (falls nicht schon laufend)

```bash
cd ~/workspace/sa-ii/01_Startumgebung
sudo docker compose up -d --build
sudo docker compose ps -a
```

Etwa 25 Sekunden warten. Erwartet: `web` und `api` healthy, `worker`
running/unhealthy. Den Worker nicht reparieren.

**2. Collector installieren** (einmalig)

```bash
cd ~/workspace/sa-ii/02_Monitoring/collector
chmod +x scripts/*.sh
sudo ./scripts/install-collector.sh
./scripts/check-snapshot.sh
```

Der letzte Befehl muss "Snapshot frisch, Datenerfassung ok" melden. Erst dann
weiter, sonst zeigt das Dashboard korrekterweise nur UNKNOWN.

**3. Dashboard starten**

```bash
cd ~/workspace/sa-ii/02_Monitoring
sudo docker compose up -d --build
sudo docker compose ps
```

**4. AI-Relay installieren** (einmalig, fuer Phase D)

```bash
cd ~/workspace/sa-ii/02_Monitoring/ai-relay
chmod +x scripts/*.sh
sudo ./scripts/install-relay.sh
./scripts/check-relay.sh --probe
```

Die vollstaendige Reihenfolge mit Pruefpunkten steht in `DEPLOY.md`.

## Erreichen

Im Browser **auf der Ubuntu-VM**:

```
http://127.0.0.1:8090
```

Auf der Kommandozeile:

```bash
curl -fsS http://127.0.0.1:8090/health   | python3 -m json.tool
curl -fsS http://127.0.0.1:8090/api/state | python3 -m json.tool
```

Die Vorgabe `127.0.0.1` ist Absicht: der Port ist nur auf der VM selbst
erreichbar, nicht im Netz. Das gilt genauso fuer `8081` der Laborumgebung.

### Zugriff von einem anderen Rechner

Drei Wege, von eng nach offen. Welcher genommen wurde, gehoert in den
Security-Teil des Berichts.

**1. SSH-Tunnel, Bindung bleibt lokal (engste Variante)**

```bash
# auf der Ubuntu-VM, einmalig
sudo apt install -y openssh-server && sudo systemctl enable --now ssh
hostname -I

# auf dem anderen Rechner, Terminal offen lassen
ssh -N -L 8090:127.0.0.1:8090 <benutzer>@<ubuntu-ip>
```

Danach dort `http://127.0.0.1:8090`. Der Port bleibt auf der VM loopback-only,
der Zugriff ist authentifiziert und verschluesselt.

**2. Freigabe nur im isolierten Host-only-Netz**

```bash
cd ~/workspace/sa-ii/02_Monitoring
DASHBOARD_BIND=192.168.56.10 sudo -E docker compose up -d   # IP der VM einsetzen
```

Erreichbar unter `http://192.168.56.10:8090`, aber nur auf dieser einen
Schnittstelle. Das ist der brauchbare Mittelweg, wenn kein SSH laufen soll.

**3. Freigabe auf allen Schnittstellen**

```bash
DASHBOARD_BIND=0.0.0.0 sudo -E docker compose up -d
```

Funktioniert sofort, gibt den Port aber jedem im Netz frei. Das Dashboard hat
keine Authentifizierung: wer die Adresse kennt, sieht Containernamen, Images,
Ports und Logzeilen. Im abgeschotteten Labornetz vertretbar, aber zu begruenden
und nach der Demonstration zurueckzunehmen:

```bash
sudo docker compose up -d        # ohne Variable, wieder 127.0.0.1
sudo docker compose port dashboard 8000   # Bindung kontrollieren
```

Zwei Hinweise dazu:

- Eine geaenderte Bind-Adresse verlangt **Containerneuerstellung** (`up -d`).
  `restart` uebernimmt geaenderte Compose-Variablen nicht.
- `sudo -E` ist noetig, damit `sudo` die Variable durchreicht. Eine `.env`-Datei
  im Ordner wuerde den Wert ebenfalls setzen, dann aber unbemerkt bei jedem
  Start. Besser die Variable explizit am Befehl mitgeben.

Die Regel aus dem Aufgabenblatt, dass `0.0.0.0` keine zulaessige Abkuerzung ist,
betrifft die Freigabe von **Ollama**. Fuer die eigene Anwendung ist die Freigabe
erlaubt, sie muss nur begruendet sein. Deshalb bleibt die Vorgabe eng und die
Oeffnung ein sichtbarer, zurueckgenommener Einzelschritt.

## Endpunkte des Dashboards

| Route | Inhalt |
|---|---|
| `/` | Weboberflaeche, aktualisiert sich alle 5 s |
| `/api/state` | aufbereiteter Zustand als JSON |
| `/api/ai` | Erreichbarkeit der AI, letzte Analyse, letzter Fehlversuch |
| `POST /api/analyze` | loest eine Analyse aus (das macht auch der Button) |
| `/health` | Health des Dashboards, maschinenlesbar, HTTP 200 |
| sonst | HTTP 404 mit JSON-Fehler und gueltigen Routen |

`/health` beschreibt ausschliesslich das Dashboard. Weder ein `unhealthy worker`
noch ein toter Collector noch eine nicht erreichbare AI machen das Dashboard
unhealthy; sie erscheinen in `data_status` beziehungsweise unter `/api/ai`.
Andernfalls wuerde die Ueberwachung beim ersten Vorfall selbst ausfallen und gar
nichts mehr zeigen.

## Stoppen und zuruecksetzen

```bash
cd ~/workspace/sa-ii/02_Monitoring
sudo docker compose down                      # nur das Dashboard
sudo systemctl stop hf-ops-collector          # Collector anhalten
sudo ./collector/scripts/install-collector.sh --uninstall   # Collector entfernen
```

Die Laborumgebung wird getrennt gestoppt (`cd ../01_Startumgebung && sudo docker
compose down`). Keine fremden Container loeschen.

## Datenhaltung

Das Dashboard ist zustandslos und braucht kein Volume: es haelt nichts, was eine
Containerneuerstellung ueberleben muesste. Der jeweils letzte Messstand liegt auf
dem Host unter `/var/lib/hf-ops-collector/state/snapshot.json` und uebersteht
`docker compose down` des Dashboards. Nach einem Neustart des Dashboards ist
sofort wieder der aktuelle Stand sichtbar, weil der Collector unabhaengig
weiterlaeuft. Logs der Laborcontainer bleiben an deren Lebensdauer gebunden.

## Tests und Fehlerfaelle

```bash
# Gegenprobe zur Anzeige, gleiche Logik auf der Kommandozeile
./collector/scripts/check-snapshot.sh

# Fehlerfall "Datenerfassung gestoert" mit Protokoll (Phase E, Versuch 3)
sudo DASHBOARD_URL=http://127.0.0.1:8090/health ./collector/scripts/faultcase-collector.sh
```

Erwartung dabei: Solange der Collector steht, altert der Snapshot. Ueberschreitet
das Alter die Grenze, zeigt das Dashboard fuer jeden Service "nicht ermittelbar"
mit dem zuletzt bekannten Wert als Zusatzinformation, nicht als Istzustand.
`check-snapshot.sh` liefert dabei Exit-Code 2.

## Phase D: AI-Analyse

Der Button "AI-Analyse starten" im Dashboard loest die gesamte Verarbeitung aus:
Messdaten erfassen, Prompt bauen, HTTP-Anfrage senden, Antwort verarbeiten,
anzeigen. Kein manuelles Kopieren in Open WebUI.

Die Netzwerkfrage ist mit einer Host-Komponente geloest. `127.0.0.1` ist im
Bridge-Container der Container selbst, nicht der Host. Deshalb fragt das
Dashboard nicht Ollama, sondern das `ai-relay` auf dem Gateway seines eigenen
Netzes; dieses reicht an das unveraendert nur lokal gebundene Ollama weiter.
Ollama wird nicht freigegeben, das Dashboard bekommt kein Host-Netzwerk.
Einzelheiten: `ai-relay/README.md`.

Was an das Modell geht: Servicename, Status, Prozesszustand, Health,
Fehlerserie, Neustarts, Exit-Code, Ports und wenige gekuerzte Logzeilen,
vorrangig Fehlerzeilen. Der Prompt benennt diese Daten ausdruecklich als Daten
und nicht als Anweisungen.

Was zurueckkommt, wird in die vier geforderten Elemente zerlegt: Beobachtung,
Evidenz, vermutete Ursache, naechster Schritt. Die Anzeige nennt Modell, Dauer
und die Messung, auf der die Analyse beruht, inklusive Sequenznummer.

Drei Dinge sind dabei fest verdrahtet:

- **Modelltext ist kein Messwert.** Er steht in einer eigenen Karte, ist als
  Vorschlag gekennzeichnet und ueberschreibt keine erfassten Werte.
- **Modelltext wird nie als HTML ausgefuehrt.** Alles wird escaped ausgegeben,
  zusaetzlich begrenzt eine Content-Security-Policy, was die Seite laden darf.
- **Analyse nur auf frischen Daten.** Ist die Datenlage nicht `fresh`, wird die
  Anfrage abgelehnt. Eine Analyse auf veralteten Daten waere eine Aussage ueber
  einen Zustand, der nicht gemessen ist.

Fehlerfall aus Phase E, Versuch 2:

```bash
sudo ./ai-relay/scripts/faultcase-ai.sh
```
