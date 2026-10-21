import json, os, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
API = os.getenv('API_URL', 'http://api:8000')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/', '/health'):
            self.send_error(404); return
        try:
            with urllib.request.urlopen(API + '/health', timeout=2) as r:
                json.load(r)
            status, code = 'healthy', 200
        except Exception:
            status, code = 'api unavailable', 503
        if self.path == '/health':
            body, mime = json.dumps({'status': status, 'service': 'web'}), 'application/json'
        else:
            body, mime = ('<!doctype html><meta charset="utf-8"><title>HF Operations Lab</title>'
                          '<h1>HF Operations Lab</h1><p>Web: ' + status + '</p>'
                          '<p>Die API liefert einen Demoauftrag. Prüfen Sie alle drei Container.</p>'), 'text/html; charset=utf-8'
        data = body.encode()
        self.send_response(code); self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)

if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
