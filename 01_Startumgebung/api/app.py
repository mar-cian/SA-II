import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            code, value = 200, {'status': 'healthy', 'service': 'api'}
        elif self.path == '/jobs':
            code, value = 200, {'job': 'demo-001', 'task': 'inspect-demo', 'time': datetime.now(timezone.utc).isoformat()}
        else:
            code, value = 404, {'error': 'route not found', 'valid_routes': ['/health', '/jobs']}
        body = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
