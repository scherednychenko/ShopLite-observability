#!/usr/bin/env python3
"""
Chaos variant of the ShopLite API mock: same endpoints as the repos' mock, but it
fails a configurable fraction of requests with HTTP 500 so the load-tool
dashboards show real errors / KO (for demo screenshots). It is NEVER used in a
normal run - the feed scripts only start it when MOCK_FAIL_RATE is set.

  GET  /api/catalog     -> 200 {"items":[...]}   (or 500 with prob FAIL_RATE)
  POST /api/cart/items  -> 201 {"cartId": ...}    (or 500 with prob FAIL_RATE)
  POST /api/orders      -> 201 {"orderId": ...}   (or 500 with prob FAIL_RATE)

Env: FAIL_RATE (0..1, default 0.12). Usage: python3 chaos_mock.py [port]
"""
import json
import os
import random
import sys
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FAIL_RATE = float(os.getenv("FAIL_RATE", "0.12"))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _drain_body(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            self.rfile.read(length)

    def _maybe_fail(self):
        if random.random() < FAIL_RATE:
            self._send(500, {"error": "chaos: injected failure"})
            return True
        return False

    def do_GET(self):
        if self.path.split("?")[0] == "/api/catalog":
            if self._maybe_fail():
                return
            self._send(200, {"items": [{"productId": p} for p in (1001, 1002, 1003)]})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        self._drain_body()
        path = self.path.split("?")[0]
        if path == "/api/cart/items":
            if self._maybe_fail():
                return
            self._send(201, {"cartId": str(uuid.uuid4())})
        elif path == "/api/orders":
            if self._maybe_fail():
                return
            self._send(201, {"orderId": str(uuid.uuid4())})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"ShopLite CHAOS mock on http://0.0.0.0:{port} (FAIL_RATE={FAIL_RATE})")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
