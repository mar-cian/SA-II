import json, os, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
API = os.getenv('API_URL', 'http://api:8000')
JOB_PATH = os.getenv('JOB_PATH', '/jobs')
state = {'last_success': 0.0, 'last_error': 'no successful job yet'}
lock = threading.Lock()

def work():
    while True:
        try:
            with urllib.request.urlopen(API + JOB_PATH, timeout=2) as r:
                job = json.load(r)
            with lock:
                state.update(last_success=time.monotonic(), last_error='')
            print('INFO processed job=' + job['job'], flush=True)
        except Exception as exc:
            with lock:
                state['last_error'] = str(exc)
            print(f'ERROR job fetch failed path={JOB_PATH}: {exc}', flush=True)
        time.sleep(3)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/health':
            self.send_error(404); return
        with lock:
            ok = time.monotonic() - state['last_success'] < 12 and not state['last_error']
            body = json.dumps({'status': 'healthy' if ok else 'unhealthy', 'error': state['last_error']}).encode()
        self.send_response(200 if ok else 503)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

if __name__ == '__main__':
    threading.Thread(target=work, daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
