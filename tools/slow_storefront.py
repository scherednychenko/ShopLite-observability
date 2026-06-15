#!/usr/bin/env python3
"""
Slow variant of the ShopLite storefront: serves the same static pages/assets the
nginx mock serves, but sleeps DELAY_MS before every response. sitespeed.io's
connectivity throttling can't run on Docker Desktop (no `ifb` kernel module for
the tc engine; tsproxy doesn't attach), so feed-sitespeed.sh uses this in SLOW
mode to push Core Web Vitals over Google's thresholds -> red gauges/cells.

Serves files from the working directory (mount the ui-perf storefront html there).
Env: DELAY_MS (default 800). Usage: python3 slow_storefront.py [port]
"""
import os
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

DELAY = float(os.getenv("DELAY_MS", "800")) / 1000.0


class SlowHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        time.sleep(DELAY)
        super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    print(f"ShopLite SLOW storefront on :{port} (DELAY_MS={DELAY*1000:.0f})")
    ThreadingHTTPServer(("0.0.0.0", port), SlowHandler).serve_forever()
