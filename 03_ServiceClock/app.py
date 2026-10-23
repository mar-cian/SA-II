#!/usr/bin/env python3
"""
Service Clock - kleine zustandslose Anwendung (Auftrag 3).

Zeigt den eigenen Betriebszustand: konfigurierter Name, Status, Zeit in einer
konfigurierten Zeitzone, Laufzeit seit Prozessstart und Anzahl bedienter
Anfragen.

Entwurf und Abgrenzung stehen in PFLICHTENHEFT.md.

Eigenschaften, die bewusst so gebaut sind:
    - Nur Standardbibliothek, kein Paket nachzuladen.
    - Zustandslos: nichts wird auf Platte geschrieben, kein Volume noetig.
    - Jeder Wert, der von aussen kommt, wird in HTML escaped ausgegeben.
      Das betrifft vor allem SERVICE_NAME aus dem Environment.
    - Eine unbekannte Zeitzone fuehrt nicht zum Absturz: der Prozess laeuft
      weiter, faellt auf UTC zurueck und meldet sich als degraded. Damit
      bleiben Prozesszustand und Health-Status unterscheidbar.
    - Startphase: in den ersten WARMUP_SECONDS meldet /health starting mit
      HTTP 503. Dazu passt start_period im Healthcheck.
"""

from __future__ import annotations

import html
import json
import os
import signal
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    from zoneinfo import ZoneInfo
except ImportError:  # Python ohne zoneinfo
    ZoneInfo = None  # type: ignore

APP_NAME = "Service Clock"
APP_VERSION = "1.0.0"

# APP_NAME ist der Name aus der Vorgabe des Arbeitsblatts, SERVICE_NAME der
# eigene. Beide werden akzeptiert, damit die Konfiguration aus beiden Quellen
# wirkt; SERVICE_NAME hat Vorrang, wenn beide gesetzt sind.
SERVICE_NAME = os.getenv("SERVICE_NAME") or os.getenv("APP_NAME") or "HF Service Clock"
CLOCK_TZ = os.getenv("CLOCK_TZ", "Europe/Zurich")
PORT = int(os.getenv("PORT", "8000"))
WARMUP_SECONDS = int(os.getenv("WARMUP_SECONDS", "5"))
REFRESH_SECONDS = int(os.getenv("REFRESH_SECONDS", "2"))

STARTED_AT = time.time()
STARTED_AT_ISO = datetime.now(timezone.utc).isoformat(timespec="seconds")

# Zaehler im Arbeitsspeicher. Wird bei jedem Prozessstart auf 0 gesetzt, das
# ist im Pflichtenheft als fluechtiger Wert festgehalten.
_counter_lock = threading.Lock()
_requests_served = 0

# Zeitzone einmal beim Start aufloesen. Schlaegt das fehl, laeuft die Anwendung
# in UTC weiter und meldet den Grund ueber /health.
ZONE = timezone.utc
ZONE_ERROR: str | None = None
if ZoneInfo is None:
    ZONE_ERROR = "Diese Python-Version kennt kein zoneinfo, Anzeige in UTC."
else:
    try:
        ZONE = ZoneInfo(CLOCK_TZ)
    except Exception as exc:
        ZONE_ERROR = (f"Zeitzone '{CLOCK_TZ}' ist nicht aufloesbar "
                      f"({type(exc).__name__}). Anzeige in UTC. "
                      f"Fehlen im Image die Zeitzonendaten, hilft das Paket tzdata.")


def count_request() -> int:
    global _requests_served
    with _counter_lock:
        _requests_served += 1
        return _requests_served


def state() -> dict:
    """Aktueller Zustand. Einzige Quelle fuer alle drei Endpunkte."""
    uptime = time.time() - STARTED_AT
    if ZONE_ERROR:
        status, reason, code = "degraded", ZONE_ERROR, 503
    elif uptime < WARMUP_SECONDS:
        status = "starting"
        reason = (f"Startphase, noch {max(0, WARMUP_SECONDS - uptime):.1f} s "
                  f"bis zur Betriebsbereitschaft.")
        code = 503
    else:
        status, reason, code = "healthy", "Betriebsbereit.", 200

    now = datetime.now(ZONE)
    with _counter_lock:
        served = _requests_served
    return {
        "service": SERVICE_NAME,
        "application": APP_NAME,
        "version": APP_VERSION,
        "status": status,
        "status_reason": reason,
        "http_status": code,
        "timezone": CLOCK_TZ if not ZONE_ERROR else "UTC (Rueckfall)",
        "now": now.isoformat(timespec="seconds"),
        "now_human": now.strftime("%d.%m.%Y %H:%M:%S"),
        "started_at": STARTED_AT_ISO,
        "uptime_seconds": round(uptime, 1),
        "requests_served": served,
        "stateless": True,
        "note": ("Zustandslos: started_at, uptime_seconds und requests_served "
                 "werden bei jedem Prozessstart zurueckgesetzt."),
    }


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

STYLE = """
:root{--bg:#f6f7f9;--card:#fff;--fg:#14171c;--muted:#5c6570;--line:#dfe3e8;
--ok:#1a7f46;--warn:#9a6700;--bad:#b3261e}
@media (prefers-color-scheme:dark){:root{--bg:#14171c;--card:#1c2026;--fg:#e9ecef;
--muted:#9aa4af;--line:#2c323a;--ok:#4ac07c;--warn:#e0a83a;--bad:#ff6b5e}}
*{box-sizing:border-box}
body{margin:0;padding:32px 16px;background:var(--bg);color:var(--fg);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:560px;margin:0 auto}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:22px 24px}
h1{font-size:21px;margin:0 0 4px;overflow-wrap:anywhere}
.sub{color:var(--muted);font-size:13px;margin:0 0 18px}
.pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;
font-weight:600;border:1px solid;margin-left:6px;vertical-align:2px}
.s-healthy{color:var(--ok);border-color:var(--ok);background:rgba(74,192,124,.12)}
.s-starting{color:var(--warn);border-color:var(--warn);background:rgba(224,168,58,.12)}
.s-degraded{color:var(--bad);border-color:var(--bad);background:rgba(255,107,94,.12)}
.clock{font-size:34px;font-weight:650;letter-spacing:.5px;margin:10px 0 2px;
font-variant-numeric:tabular-nums}
.zone{color:var(--muted);font-size:12px;margin:0 0 18px}
dl{display:grid;grid-template-columns:auto 1fr;gap:6px 16px;margin:0;font-size:13px}
dt{color:var(--muted)}
dd{margin:0;font-variant-numeric:tabular-nums}
.reason{margin:14px 0 0;font-size:13px;color:var(--muted)}
.reason.bad{color:var(--bad)}
footer{margin:16px 0 0;font-size:12px;color:var(--muted)}
a{color:inherit}
"""


def esc(value) -> str:
    """Alles, was von aussen kommt, wird als Text ausgegeben, nie als Markup."""
    if value is None:
        return "-"
    if isinstance(value, bool):
        value = "ja" if value else "nein"
    return html.escape(str(value), quote=True)


def render_page(data: dict) -> str:
    status = data["status"]
    reason_class = "reason bad" if status == "degraded" else "reason"
    return f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="{REFRESH_SECONDS}">
<title>{esc(data['service'])}</title>
<style>{STYLE}</style>
</head>
<body>
<div class="wrap"><div class="card">
  <h1>{esc(data['service'])}<span class="pill s-{esc(status)}">{esc(status)}</span></h1>
  <p class="sub">{esc(data['application'])} {esc(data['version'])}</p>

  <p class="clock">{esc(data['now_human'])}</p>
  <p class="zone">Zeitzone {esc(data['timezone'])}</p>

  <dl>
    <dt>Laufzeit</dt><dd>{esc(data['uptime_seconds'])} s</dd>
    <dt>Gestartet</dt><dd>{esc(data['started_at'])}</dd>
    <dt>Anfragen</dt><dd>{esc(data['requests_served'])}</dd>
    <dt>Zustandslos</dt><dd>{esc(data['stateless'])}</dd>
  </dl>

  <p class="{reason_class}">{esc(data['status_reason'])}</p>
  <footer>
    Maschinenlesbar: <a href="/health">/health</a> und <a href="/api/clock">/api/clock</a>.
    Seite aktualisiert sich alle {esc(REFRESH_SECONDS)} s.
  </footer>
</div></div>
</body>
</html>"""


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = f"service-clock/{APP_VERSION}"

    def _send(self, code: int, body: bytes, mime: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; style-src 'unsafe-inline'; "
                         "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def _json(self, code: int, payload: dict) -> None:
        self._send(code, json.dumps(payload, ensure_ascii=False, indent=2).encode(),
                   "application/json; charset=utf-8")

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        count_request()
        data = state()
        if path == "/":
            self._send(data["http_status"], render_page(data).encode(),
                       "text/html; charset=utf-8")
        elif path == "/health":
            self._json(data["http_status"], {
                "status": data["status"],
                "service": data["service"],
                "version": data["version"],
                "reason": data["status_reason"],
                "uptime_seconds": data["uptime_seconds"],
                "started_at": data["started_at"],
                "requests_served": data["requests_served"],
                "timezone": data["timezone"],
            })
        elif path in ("/api/clock", "/api/info"):
            # /api/info ist der Vertrag aus dem Arbeitsblatt: application,
            # status, time, uptime_seconds. /api/clock liefert dasselbe unter
            # den eigenen Feldnamen. Beide Routen antworten identisch, damit
            # ein Aufrufer sich auf beide Schreibweisen stuetzen kann.
            payload = dict(data)
            payload["application"] = data["service"]
            payload["time"] = data["now"]
            self._json(data["http_status"], payload)
        else:
            self._json(404, {
                "error": "route not found",
                "path": path,
                "valid_routes": ["/", "/health", "/api/info", "/api/clock"],
            })

    def _reject_method(self) -> None:
        self.send_response(405)
        self.send_header("Allow", "GET")
        body = json.dumps({
            "error": "method not allowed",
            "allowed": ["GET"],
        }, ensure_ascii=False, indent=2).encode()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # Alles ausser GET wird mit 405 und Allow-Kopfzeile beantwortet.
    do_POST = do_PUT = do_DELETE = do_PATCH = _reject_method  # noqa: N815

    def do_HEAD(self) -> None:  # noqa: N802
        data = state()
        self.send_response(data["http_status"])
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()

    def log_message(self, fmt: str, *args) -> None:
        print(f"INFO {self.address_string()} {fmt % args}", flush=True)


class ClockServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def handle_signal(signum, _frame) -> None:
    print(f"INFO Signal {signum} empfangen, beende", flush=True)
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    print(f"INFO {APP_NAME} {APP_VERSION} startet auf Port {PORT}", flush=True)
    print(f"INFO Name '{SERVICE_NAME}', Zeitzone '{CLOCK_TZ}', "
          f"Startphase {WARMUP_SECONDS}s", flush=True)
    if ZONE_ERROR:
        print(f"WARN {ZONE_ERROR}", flush=True)
    ClockServer(("0.0.0.0", PORT), Handler).serve_forever()
