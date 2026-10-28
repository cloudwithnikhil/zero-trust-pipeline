from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import socket
from datetime import datetime, timezone

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/health", "/ready"):
            self.send_error(404, "Not Found")
            return

        payload = {
            "service": "zero-trust-demo",
            "status": "healthy",
            "hostname": socket.gethostname(),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

        body = json.dumps(payload, indent=2).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(f"{self.client_address[0]} - {format % args}")

port = int(os.environ.get("PORT", "8080"))
server = HTTPServer(("0.0.0.0", port), Handler)
print(f"Zero Trust Demo listening on port {port}")
server.serve_forever()
