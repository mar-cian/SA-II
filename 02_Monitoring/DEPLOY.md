# Deployment in sauberer Reihenfolge

Alles auf der Ubuntu-VM. Jeder Schritt hat einen Pruefpunkt. Stimmt der nicht,
erst dort weitermachen, nicht zum naechsten Schritt gehen.

## 0. Voraussetzungen

```bash
sudo docker info | head -3
sudo docker compose version
python3 --version
curl -fsS http://127.0.0.1:8080/api/tags | head -c 200   # Ollama
```

Pruefpunkt: Docker laeuft, Compose vorhanden, Ollama antwortet mit einer
Modelliste. Fehlt ein Modell, erst klaeren, welche Namen vorhanden sind, und
`AIR_ALLOWED_MODELS` sowie `AI_MODEL` spaeter anpassen.

## 1. Paket auf die VM

Ueber das Repo. Einmalig einen Schluessel der VM in GitLab hinterlegen:

```bash
ssh-keygen -t ed25519 -C "ubuntu-vm sa-ii" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub        # Inhalt in GitLab unter SSH Keys eintragen
ssh -T git@git.gibb.ch           # Fingerprint einmal bestaetigen
```

Dann klonen:

```bash
mkdir -p ~/workspace && cd ~/workspace
git clone git@git.gibb.ch:gri140834/sa-ii.git
cd ~/workspace/sa-ii/02_Monitoring
chmod +x collector/scripts/*.sh ai-relay/scripts/*.sh
python3 collector/hf_collector.py --selftest | tail -1
python3 ai-relay/hf_ai_relay.py  --selftest | tail -1
```

Spaetere Aenderungen holst du mit `git pull` im Repo-Ordner.

Pruefpunkt: Beide Selbsttests melden "Selbsttest bestanden".

Die folgenden Schritte gehen von `~/workspace/sa-ii` als Repo-Ordner aus. Liegt
er woanders, Pfade entsprechend anpassen. Laeuft die Laborumgebung noch aus einem
frueheren Ordner, kann sie dort bleiben: Compose erkennt das Projekt am Namen
`hf-ops-lab`, nicht am Pfad.

## 2. Laborumgebung starten

```bash
cd ~/workspace/sa-ii/01_Startumgebung
sudo docker compose up -d --build
sleep 25
sudo docker compose ps -a
```

Pruefpunkt: `api` und `web` healthy, `worker` running/unhealthy. Den Worker
nicht reparieren, das Dashboard soll genau diesen Fehler zeigen.

## 3. Collector installieren

```bash
cd ~/workspace/sa-ii/02_Monitoring/collector
sudo ./scripts/install-collector.sh
./scripts/check-snapshot.sh
```

Pruefpunkt: "Snapshot frisch, Datenerfassung ok", Exit-Code 0, und in der
Tabelle steht `worker fehlerhaft`.

## 4. Dashboard starten

```bash
cd ~/workspace/sa-ii/02_Monitoring
sudo docker compose up -d --build
sudo docker compose ps
curl -fsS http://127.0.0.1:8082/health | python3 -m json.tool
```

Pruefpunkt: Container healthy, `/health` liefert `"status": "healthy"` und
`"data_status": "fresh"`. Im Browser auf der VM: `http://127.0.0.1:8082`.

Dieser Schritt legt das Netz `hf-ops-dashboard` mit dem Gateway
`172.31.240.1` an. Darauf lauscht im naechsten Schritt das Relay.

## 5. AI-Relay installieren

```bash
cd ~/workspace/sa-ii/02_Monitoring/ai-relay
sudo ./scripts/install-relay.sh
./scripts/check-relay.sh
./scripts/check-relay.sh --probe
```

Pruefpunkt: "Relay laeuft, Ollama erreichbar, Vorgabemodell vorhanden",
Exit-Code 0. `--probe` liefert einen kurzen Modellsatz. Die Gegenprobe mit dem
nicht freigegebenen Modell muss HTTP 403 ergeben.

## 6. Gesamtprobe

```bash
curl -fsS http://127.0.0.1:8082/api/ai | python3 -m json.tool | head -12
curl -s -X POST http://127.0.0.1:8082/api/analyze | python3 -m json.tool | head -20
```

Pruefpunkt: `/api/ai` meldet `"status": "available"`. Die Analyse liefert
`"ok": true` und vier Abschnitte unter `sections`. Im Browser erscheint die
Karte "AI-Analyse" mit Beobachtung, Evidenz, vermuteter Ursache und naechstem
Schritt sowie der Angabe, auf welcher Messung sie beruht.

## 7. Zugriff vom Kali

Bindung bleibt lokal, der Zugriff laeuft ueber einen Tunnel.

Einmalig auf der Ubuntu-VM:

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
hostname -I
```

Auf dem Kali, Terminal offen lassen:

```bash
ssh -N -L 8082:127.0.0.1:8082 vmadmin@<ubuntu-ip>
```

Pruefpunkt: Im Kali-Browser `http://127.0.0.1:8082`. Die Alternative mit
`DASHBOARD_BIND` ist in `README.md` beschrieben; sie oeffnet den Port im Netz
und gehoert dann als Abweichung ins Protokoll.

## 8. Nachweise fuer die Abgabe

```bash
cd ~/workspace/sa-ii/02_Monitoring
sudo ./collector/scripts/faultcase-collector.sh    # Erfassung gestoert
sudo ./ai-relay/scripts/faultcase-ai.sh            # AI nicht erreichbar
```

Beide Skripte schreiben ein Protokoll mit Zeitstempeln in das aktuelle
Verzeichnis: Soll, Eingriff, Beobachtung, Beleg, Wiederherstellung.

## 9. Nach einer Codeaenderung neu deployen

```bash
# Dashboard: Image neu bauen und Container neu erstellen
cd ~/workspace/sa-ii/02_Monitoring
sudo docker compose up -d --build

# Collector oder Relay: Datei neu installieren und Dienst neu starten
sudo ./collector/scripts/install-collector.sh
sudo ./ai-relay/scripts/install-relay.sh
```

`restart` genuegt nicht, wenn sich Compose-Variablen oder Ports geaendert haben.
Das verlangt Containerneuerstellung mit `up -d`.

## 10. Stoppen und zuruecksetzen

```bash
cd ~/workspace/sa-ii/02_Monitoring
sudo docker compose down                                # Dashboard
sudo systemctl stop hf-ops-collector hf-ops-ai-relay    # Host-Dienste anhalten
sudo ./collector/scripts/install-collector.sh --uninstall
sudo ./ai-relay/scripts/install-relay.sh --uninstall
cd ../01_Startumgebung && sudo docker compose down      # Laborumgebung
```

Keine fremden Container loeschen, Ollama und Open WebUI nicht anfassen.

## 11. Wenn etwas klemmt

| Symptom | Erste Pruefung |
|---|---|
| Dashboard zeigt "Keine Messdaten" | `sudo systemctl status hf-ops-collector`, dann `./collector/scripts/check-snapshot.sh` |
| Dashboard zeigt "Daten veraltet" | laeuft der Collector noch? `sudo journalctl -u hf-ops-collector -n 30` |
| Alle Services "nicht ermittelbar" | Docker-Zugriff des Collectors, siehe Meldung im Snapshot unter `errors` |
| AI "Relay nicht erreichbar" | `sudo systemctl status hf-ops-ai-relay`, dann `ip -4 addr \| grep 172.31.240` |
| Relay laeuft, Adresse fehlt am Host | Dashboard einmal starten, das legt das Netz an |
| AI "Ollama antwortet nicht" | `curl -fsS http://127.0.0.1:8080/api/tags` auf dem Host |
| AI "Modell nicht vorhanden" | `ollama list`, danach `AI_MODEL` in `compose.yaml` und `AIR_ALLOWED_MODELS` anpassen |
| Analyse bricht mit `relay_busy` ab | es laeuft bereits eine Anfrage, kurz warten |
| Analyse abgelehnt, `data_not_fresh` | das ist gewollt: zuerst den Collector in Ordnung bringen |
| Port 8082 belegt | `ss -ltnp \| grep 8082`, Port in `compose.yaml` aendern |
| Container erreicht Relay nicht | `sudo ufw status`; falls aktiv: `sudo ufw allow from 172.31.240.0/24 to 172.31.240.1 port 8899 proto tcp` |
