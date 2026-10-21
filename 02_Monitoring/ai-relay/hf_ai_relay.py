#!/usr/bin/env python3
"""
hf_ai_relay.py - Host-Komponente fuer den AI-Zugriff (Auftrag 2, Phase D).

Die Netzwerkfrage
    Ollama lauscht auf 127.0.0.1:8080 des Ubuntu-Hosts. In einem Bridge-Container
    ist 127.0.0.1 der Container selbst, nicht der Host. Der Dashboard-Container
    erreicht Ollama daher nicht direkt. Eine Freigabe von Ollama auf 0.0.0.0 ist
    laut Aufgabenblatt keine zulaessige Abkuerzung, Host-Netzwerk fuer das
    Dashboard waere die zweite Option.

    Dieses Relay ist die dritte, engste Option: ein kleiner Host-Prozess, der auf
    der Gateway-Adresse des Dashboard-Netzes lauscht und die Anfrage an das
    weiterhin nur lokal gebundene Ollama weiterreicht. Ollama bleibt unveraendert.

Warum kein transparenter Proxy
    Das Relay reicht nicht die Ollama-API durch, sondern bietet genau einen
    fachlichen Endpunkt an. Der Container kann damit kein Modell laden, loeschen
    oder erzeugen, auch wenn er es versuchte. Erlaubt sind nur die Modelle aus
    der Allowlist, stream ist immer false, Laenge und Dauer sind gedeckelt und es
    laeuft hoechstens eine Anfrage gleichzeitig.

Rechte
    Das Relay braucht keinen Docker-Zugriff und keine Hostrechte. Es laeuft unter
    systemd als DynamicUser ohne eigenes Home und ohne Schreibrechte.

Endpunkte
    GET  /health      Zustand des Relays und Erreichbarkeit von Ollama
    GET  /v1/models   Namen der vorhandenen Modelle (aus /api/tags)
    POST /v1/analyze  {"model": "...", "prompt": "...", "num_predict": 300}
                      -> {"ok": true, "content": "...", "model": "...", ...}
    sonst             404 mit JSON

Konfiguration ueber Environment Variables, siehe relay.env.example.
"""

from __future__ import annotations

import json
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RELAY_NAME = "hf-ops-ai-relay"
RELAY_VERSION = "1.0.0"

# Gateway des Dashboard-Netzes aus compose.yaml. Nur Container in diesem Netz
# erreichen das Relay; vom LAN aus ist es nicht sichtbar.
BIND_HOST = os.getenv("AIR_BIND_HOST", "172.31.240.1")
BIND_PORT = int(os.getenv("AIR_BIND_PORT", "8899"))

# Ollama bleibt dort, wo es ist.
OLLAMA_URL = os.getenv("AIR_OLLAMA_URL", "http://127.0.0.1:8080").rstrip("/")
ALLOWED_MODELS = tuple(
    m.strip() for m in os.getenv("AIR_ALLOWED_MODELS", "coder-schnell,coder-genau").split(",")
    if m.strip()
)
DEFAULT_MODEL = os.getenv("AIR_DEFAULT_MODEL", ALLOWED_MODELS[0] if ALLOWED_MODELS else "coder-schnell")

# Grenzen. Sie schuetzen den Host vor einer Dauerlast durch das Dashboard und
# halten die Antwortzeit im Rahmen des Aufgabenblatts (curl --max-time 100).
MAX_REQUEST_BYTES = int(os.getenv("AIR_MAX_REQUEST_BYTES", "16384"))
MAX_NUM_PREDICT = int(os.getenv("AIR_MAX_NUM_PREDICT", "400"))
OLLAMA_TIMEOUT = int(os.getenv("AIR_OLLAMA_TIMEOUT", "100"))
PROBE_TIMEOUT = int(os.getenv("AIR_PROBE_TIMEOUT", "3"))
NUM_CTX = int(os.getenv("AIR_NUM_CTX", "4096"))

STARTED_AT = time.time()

# Nur eine Anfrage gleichzeitig: das Aufgabenblatt empfiehlt das ausdruecklich,
# und ein lokales Modell wird unter Parallellast unbrauchbar langsam.
_slot = threading.BoundedSemaphore(1)
_stats_lock = threading.Lock()
_stats = {"requests": 0, "ok": 0, "failed": 0, "last_error": None, "last_at": None}


class RelayError(Exception):
    def __init__(self, status: int, code: str, message: str, detail: str | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.detail = detail


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(msg: str) -> None:
    print(f"{now_iso()} {msg}", flush=True)


# ---------------------------------------------------------------------------
# Ollama
# ---------------------------------------------------------------------------

def call_ollama(path: str, payload: dict | None, timeout: int) -> dict:
    """
    Einziger Weg nach draussen. Das Ziel steht fest in der Konfiguration, der
    Aufrufer kann weder Host noch Pfad beeinflussen.
    """
    url = f"{OLLAMA_URL}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        method="POST" if data is not None else "GET",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", "replace")[:300]
        except Exception:
            pass
        raise RelayError(502, "ollama_http_error",
                         f"Ollama antwortete mit HTTP {exc.code}.",
                         body or str(exc)) from exc
    except urllib.error.URLError as exc:
        reason = getattr(exc, "reason", exc)
        if isinstance(reason, socket.timeout):
            raise RelayError(504, "ollama_timeout",
                             f"Ollama hat innerhalb von {timeout}s nicht geantwortet.",
                             str(reason)) from exc
        raise RelayError(502, "ollama_unreachable",
                         f"Ollama unter {OLLAMA_URL} nicht erreichbar.",
                         str(reason)) from exc
    except socket.timeout as exc:
        raise RelayError(504, "ollama_timeout",
                         f"Ollama hat innerhalb von {timeout}s nicht geantwortet.",
                         str(exc)) from exc
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RelayError(502, "ollama_bad_response",
                         "Ollama lieferte kein gueltiges JSON.",
                         raw[:200].decode("utf-8", "replace")) from exc


def list_models() -> list[str]:
    data = call_ollama("/api/tags", None, PROBE_TIMEOUT)
    names = []
    for item in data.get("models") or []:
        name = item.get("name") or item.get("model")
        if name:
            names.append(name)
    return names


def model_present(model: str, available: list[str]) -> bool:
    # Ollama fuehrt Modelle teils mit Tag ("name:latest").
    return any(name == model or name.split(":", 1)[0] == model for name in available)


def analyze(model: str, prompt: str, num_predict: int) -> dict:
    available = list_models()
    if not model_present(model, available):
        raise RelayError(502, "model_missing",
                         f"Modell '{model}' ist in Ollama nicht vorhanden.",
                         f"vorhanden: {', '.join(available) or 'keine'}")
    payload = {
        "model": model,
        "stream": False,                      # immer, unabhaengig vom Aufrufer
        "messages": [{"role": "user", "content": prompt}],
        "options": {"num_predict": num_predict, "num_ctx": NUM_CTX},
    }
    started = time.monotonic()
    data = call_ollama("/api/chat", payload, OLLAMA_TIMEOUT)
    duration_ms = round((time.monotonic() - started) * 1000, 1)

    content = ((data.get("message") or {}).get("content") or "").strip()
    if not content:
        raise RelayError(502, "empty_answer",
                         "Ollama lieferte eine leere Antwort.",
                         json.dumps(data)[:300])
    eval_count = data.get("eval_count")
    truncated = bool(eval_count and eval_count >= num_predict)
    return {
        "ok": True,
        "model": model,
        "content": content,
        "duration_ms": duration_ms,
        "eval_count": eval_count,
        "num_predict": num_predict,
        "truncated": truncated,
        "answered_at": now_iso(),
        "note": ("Modelltext ist ein Vorschlag, kein Messwert. Nachweis ist erst "
                 "ein reproduzierbarer Test."),
    }


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = f"{RELAY_NAME}/{RELAY_VERSION}"
    protocol_version = "HTTP/1.1"

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if status >= 400:
            # Bei einer Ablehnung wurde der Anfragekoerper teils nicht gelesen.
            # Ohne Verbindungsabbau wuerde der Rest als naechste Anfrage gedeutet.
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def _fail(self, exc: RelayError) -> None:
        with _stats_lock:
            _stats["failed"] += 1
            _stats["last_error"] = f"{exc.code}: {exc.message}"
            _stats["last_at"] = now_iso()
        log(f"WARN {exc.code} {exc.message} | {exc.detail or ''}")
        self._json(exc.status, {
            "ok": False, "error": exc.code, "message": exc.message, "detail": exc.detail,
        })

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/health":
            reachable, detail, models = True, None, []
            try:
                models = list_models()
            except RelayError as exc:
                reachable, detail = False, f"{exc.code}: {exc.message}"
            with _stats_lock:
                stats = dict(_stats)
            self._json(200, {
                "status": "healthy",
                "service": RELAY_NAME,
                "version": RELAY_VERSION,
                "uptime_seconds": round(time.time() - STARTED_AT, 1),
                "bind": f"{BIND_HOST}:{BIND_PORT}",
                "ollama_url": OLLAMA_URL,
                "ollama_reachable": reachable,
                "ollama_detail": detail,
                "models_available": models,
                "models_allowed": list(ALLOWED_MODELS),
                "default_model": DEFAULT_MODEL,
                "busy": _slot._value == 0,  # noqa: SLF001
                "stats": stats,
                "note": ("Health beschreibt das Relay. Ollama nicht erreichbar heisst "
                         "ollama_reachable=false, nicht unhealthy."),
            })
        elif path == "/v1/models":
            try:
                self._json(200, {"ok": True, "available": list_models(),
                                 "allowed": list(ALLOWED_MODELS), "default": DEFAULT_MODEL})
            except RelayError as exc:
                self._fail(exc)
        else:
            self._json(404, {"ok": False, "error": "route_not_found",
                             "valid_routes": ["/health", "/v1/models", "/v1/analyze (POST)"]})

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path != "/v1/analyze":
            self._json(404, {"ok": False, "error": "route_not_found",
                             "valid_routes": ["/v1/analyze"]})
            return
        try:
            request = self._read_request()
            if not _slot.acquire(blocking=False):
                raise RelayError(429, "relay_busy",
                                 "Es laeuft bereits eine Analyse. Bitte diese abwarten.",
                                 "Das Relay erlaubt bewusst nur eine Anfrage gleichzeitig.")
            try:
                with _stats_lock:
                    _stats["requests"] += 1
                log(f"INFO analyse model={request['model']} "
                    f"prompt_bytes={len(request['prompt'])} num_predict={request['num_predict']}")
                result = analyze(request["model"], request["prompt"], request["num_predict"])
            finally:
                _slot.release()
            with _stats_lock:
                _stats["ok"] += 1
                _stats["last_at"] = now_iso()
            log(f"INFO fertig model={result['model']} dauer={result['duration_ms']}ms "
                f"zeichen={len(result['content'])}")
            self._json(200, result)
        except RelayError as exc:
            self._fail(exc)
        except Exception as exc:  # nie stillschweigend scheitern
            self._fail(RelayError(500, "relay_error", "Unerwarteter Fehler im Relay.",
                                  f"{type(exc).__name__}: {exc}"))

    def _read_request(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise RelayError(400, "bad_request", "Content-Length fehlt oder ist ungueltig.") from None
        if length <= 0:
            raise RelayError(400, "bad_request", "Leerer Anfragekoerper.")
        if length > MAX_REQUEST_BYTES:
            raise RelayError(413, "oversized",
                             f"Anfrage ist groesser als {MAX_REQUEST_BYTES} Bytes.",
                             "Weniger Logzeilen senden oder Zeilen staerker kuerzen.")
        try:
            body = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as exc:
            raise RelayError(400, "bad_request", f"Kein gueltiges JSON: {exc}") from exc
        if not isinstance(body, dict):
            raise RelayError(400, "bad_request", "Erwartet wird ein JSON-Objekt.")

        prompt = body.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            raise RelayError(400, "bad_request", "Feld 'prompt' fehlt oder ist leer.")

        model = body.get("model") or DEFAULT_MODEL
        if model not in ALLOWED_MODELS:
            raise RelayError(403, "model_not_allowed",
                             f"Modell '{model}' ist nicht freigegeben.",
                             f"erlaubt: {', '.join(ALLOWED_MODELS)}")
        try:
            num_predict = int(body.get("num_predict") or MAX_NUM_PREDICT)
        except (TypeError, ValueError):
            num_predict = MAX_NUM_PREDICT
        num_predict = max(32, min(num_predict, MAX_NUM_PREDICT))
        return {"model": model, "prompt": prompt, "num_predict": num_predict}

    def log_message(self, fmt: str, *args) -> None:
        pass  # eigene Logzeilen oben, keine Promptinhalte im Journal


class RelayServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self) -> None:
        # IP_FREEBIND erlaubt das Binden, bevor Docker das Netz angelegt hat.
        # Ohne das muesste das Relay nach dem Dashboard starten.
        try:
            self.socket.setsockopt(socket.IPPROTO_IP, 15, 1)
        except OSError:
            pass
        super().server_bind()


def selftest() -> int:
    """Pruefungen ohne Ollama."""
    failures = 0

    class FakeHandler(Handler):
        def __init__(self):  # ohne Socket
            pass

    handler = FakeHandler()
    cases = [
        ({"prompt": "x", "model": "gibtsnicht"}, "model_not_allowed"),
        ({"model": DEFAULT_MODEL}, "bad_request"),
        ({"prompt": "   ", "model": DEFAULT_MODEL}, "bad_request"),
    ]
    for body, expected in cases:
        raw = json.dumps(body).encode()

        class Reader:
            def read(self, _n): return raw

        handler.headers = {"Content-Length": str(len(raw))}
        handler.rfile = Reader()
        try:
            handler._read_request()  # noqa: SLF001
            print(f"FAIL {body} wurde akzeptiert, erwartet {expected}")
            failures += 1
        except RelayError as exc:
            mark = "ok  " if exc.code == expected else "FAIL"
            if exc.code != expected:
                failures += 1
            print(f"{mark} {str(body)[:42]:<44} -> {exc.code}")

    raw = json.dumps({"prompt": "x", "model": DEFAULT_MODEL, "num_predict": 99999}).encode()

    class Reader2:
        def read(self, _n): return raw

    handler.headers = {"Content-Length": str(len(raw))}
    handler.rfile = Reader2()
    got = handler._read_request()["num_predict"]  # noqa: SLF001
    if got != MAX_NUM_PREDICT:
        print(f"FAIL num_predict nicht gedeckelt: {got}")
        failures += 1
    else:
        print(f"ok   num_predict wird auf {MAX_NUM_PREDICT} gedeckelt")

    big = json.dumps({"prompt": "x" * (MAX_REQUEST_BYTES + 10), "model": DEFAULT_MODEL}).encode()
    handler.headers = {"Content-Length": str(len(big))}
    try:
        handler._read_request()  # noqa: SLF001
        print("FAIL zu grosse Anfrage wurde akzeptiert")
        failures += 1
    except RelayError as exc:
        mark = "ok  " if exc.code == "oversized" else "FAIL"
        if exc.code != "oversized":
            failures += 1
        print(f"{mark} zu grosse Anfrage -> {exc.code}")

    print("Selbsttest bestanden" if failures == 0 else f"Selbsttest: {failures} Fehler")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        raise SystemExit(selftest())
    log(f"INFO {RELAY_NAME} {RELAY_VERSION} auf {BIND_HOST}:{BIND_PORT}, Ziel {OLLAMA_URL}")
    log(f"INFO erlaubte Modelle: {', '.join(ALLOWED_MODELS)} | Vorgabe: {DEFAULT_MODEL}")
    RelayServer((BIND_HOST, BIND_PORT), Handler).serve_forever()
