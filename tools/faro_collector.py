#!/usr/bin/env python3
"""
Tiny Grafana Faro receiver for the ShopLite RUM demo.

The Faro Web SDK (embedded in tools/faro/index.html) POSTs batches of telemetry
to `/collect`. In production that endpoint is Grafana Alloy (faro.receiver) →
Loki/Tempo/Prometheus, or Grafana Cloud Frontend Observability. For a *mini*
demo we keep the existing InfluxDB + Grafana stack: this script implements just
enough of the receiver to pull Web Vitals out of the payload and write them to
InfluxDB (db "faro"), so the "ShopLite — Frontend RUM (Faro)" dashboard fills in
from REAL browser sessions — INP included (unlike synthetic lab tools).

It also serves the demo page/assets (same origin as /collect), so a browser just
opens http://localhost:<port>/ and starts reporting.

Env: INFLUX_URL (default http://influxdb:8086), WEB_ROOT (default cwd), PORT.
DEMO aid only.
"""
import gzip
import json
import os
import sys
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

INFLUX_URL = os.getenv("INFLUX_URL", "http://influxdb:8086").rstrip("/")
WEB_ROOT = os.getenv("WEB_ROOT", os.getcwd())
PORT = int(os.getenv("PORT", sys.argv[1] if len(sys.argv) > 1 else "8088"))

VITALS = ("lcp", "fcp", "cls", "inp", "ttfb", "fid")  # the keys Faro puts in values{}


def esc(v):
    """Escape an InfluxDB line-protocol tag value."""
    return str(v).replace("\\", "\\\\").replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\=")


def write_points(lines):
    if not lines:
        return
    data = "\n".join(lines).encode("utf-8")
    req = urllib.request.Request(INFLUX_URL + "/write?db=faro&precision=ns", data=data, method="POST")
    try:
        urllib.request.urlopen(req, timeout=3).read()
    except Exception as e:  # don't let a write error break the browser beacon
        sys.stderr.write("influx write failed: %s\n" % e)


def handle_payload(body):
    try:
        payload = json.loads(body)
    except Exception:
        return
    meta = payload.get("meta", {})
    page = meta.get("page", {}).get("url", "unknown")
    browser = meta.get("browser", {}).get("name", "unknown")
    session = meta.get("session", {}).get("id", "unknown")
    app = meta.get("app", {})
    tags_common = "page=%s,browser=%s,session=%s,app=%s,env=%s" % (
        esc(page), esc(browser), esc(session), esc(app.get("name", "?")), esc(app.get("environment", "?")),
    )
    lines = []
    for m in payload.get("measurements", []):
        if m.get("type") != "web-vitals":
            continue
        values = m.get("values", {})
        rating = m.get("context", {}).get("rating", "unknown")
        for key in VITALS:
            if key in values and isinstance(values[key], (int, float)):
                lines.append('faro_web_vital_%s,%s,rating=%s value=%s' % (
                    key, tags_common, esc(rating), float(values[key])))
    write_points(lines)


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB_ROOT, **k)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")

    def end_headers(self):
        self._cors()
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length)
        if self.headers.get("Content-Encoding") == "gzip":
            try:
                raw = gzip.decompress(raw)
            except Exception:
                pass
        handle_payload(raw.decode("utf-8", "replace"))
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("Faro collector on :%d  → InfluxDB %s (db faro), web root %s" % (PORT, INFLUX_URL, WEB_ROOT))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
