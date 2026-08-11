import http.server, threading, json, urllib.request, time, sys

PORT = 8765
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            body = b'{"ok":true}'
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            with open('index.html', 'rb') as f:
                body = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    def log_message(self, *a): pass

srv = http.server.HTTPServer(('127.0.0.1', PORT), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
time.sleep(0.5)
html = urllib.request.urlopen(f'http://127.0.0.1:{PORT}/').read().decode('utf-8')
h = urllib.request.urlopen(f'http://127.0.0.1:{PORT}/api/health').read().decode('utf-8')
print('health:', h)
print('version:', '8.11.8' in html)
# verify todoHead structure: two direct children (no nested space-between wrapper)
import re
idx = html.find('todoHead.innerHTML')
seg = html[idx:idx+700]
# count occurrences of space-between in the todoHead block
sb = seg.count('justify-content:space-between')
print('space-between count in todoHead block:', sb)
print('---block---')
print(seg[:700])
srv.shutdown()
