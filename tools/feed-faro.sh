#!/usr/bin/env bash
# Stand up the ShopLite *Real User Monitoring* demo: a page instrumented with the
# Grafana Faro Web SDK + a tiny collector that writes the Web Vitals it reports to
# InfluxDB (db "faro"). The "ShopLite — Frontend RUM (Faro)" dashboard then fills
# in from REAL browser sessions — open the page yourself and click around.
#
#   ./tools/feed-faro.sh            # starts the collector+page on :8088, leaves it up
#   PORT=9000 ./tools/feed-faro.sh
#   ./tools/feed-faro.sh stop       # tear it down
#
# Unlike the load feeders (run-and-exit), this is a SERVER: it keeps running so a
# browser can keep reporting. This is the *field* counterpart to the lab CWV tools
# (k6 browser / sitespeed.io). In production the collector would be Grafana Alloy
# (faro.receiver) → Loki/Tempo/Prometheus, or Grafana Cloud Frontend Observability;
# here we keep the existing InfluxDB + Grafana stack. DEMO aid only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NET="${NET:-shoplite-observability_default}"
PORT="${PORT:-8088}"
NAME="shoplite-faro-obs"

cd "$ROOT"

if [ "${1:-}" = "stop" ]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  echo "✓ Faro collector stopped."
  exit 0
fi

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ ensuring the 'faro' database exists…"
docker compose exec -T influxdb influx -execute 'CREATE DATABASE faro' >/dev/null 2>&1 || true

echo "→ starting the Faro collector + demo page on :$PORT …"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --network "$NET" -p "$PORT:$PORT" \
  -e INFLUX_URL=http://influxdb:8086 -e WEB_ROOT=/www -e PORT="$PORT" \
  -v "$ROOT/tools/faro_collector.py":/faro_collector.py:ro \
  -v "$ROOT/tools/faro":/www:ro \
  python:3-alpine python /faro_collector.py >/dev/null

sleep 1
echo
echo "✓ RUM demo is live."
echo "  1) Open  http://localhost:$PORT/  in a REAL browser"
echo "  2) Click 'Add to cart' / 'Search' a few times, reload, navigate — that's your RUM session"
echo "  3) Watch Grafana → ShopLite → 'ShopLite — Frontend RUM (Faro)'  (datasource: InfluxDB-faro)"
echo
echo "  INP appears here (real interactions!) — the metric the lab k6-browser board can't capture."
echo "  Stop with:  ./tools/feed-faro.sh stop"
