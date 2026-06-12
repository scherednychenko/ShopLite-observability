#!/usr/bin/env bash
# Run the ShopLite k6 scenario so it streams metrics LIVE into this stack's
# InfluxDB, and the "ShopLite — k6 Performance" dashboard fills in.
#
#   ./tools/feed-k6.sh                       # defaults: 20 VUs, 120s
#   VUS=40 DURATION=180s ./tools/feed-k6.sh
#
# Uses the official grafana/k6 image (native InfluxDBv1 output) on this stack's
# network, pointed at influxdb:8086 (db "k6"). Open Grafana → datasource
# "InfluxDB-k6".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K6_REPO="${K6_REPO:-$ROOT/../ShopLite-load-tests-k6}"
NET="${NET:-shoplite-observability_default}"
VUS="${VUS:-20}"; DURATION="${DURATION:-120s}"; CART_SIZE="${CART_SIZE:-8}"

cd "$ROOT"

[ -f "$K6_REPO/k6/script.js" ] || {
  echo "✖ k6 repo not found at $K6_REPO — set K6_REPO=/path/to/ShopLite-load-tests-k6"; exit 1; }

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ ensuring the API mock is on the network ($NET)…"
docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true
docker run -d --name shoplite-mock-obs --network "$NET" --network-alias mock shoplite-mock >/dev/null

echo "→ running k6 ($VUS VUs, $DURATION) → influxdb:8086/k6…"
docker run --rm --network "$NET" \
  -e BASE_URL=http://mock:8080 -e VUS="$VUS" -e DURATION="$DURATION" -e CART_SIZE="$CART_SIZE" \
  -v "$K6_REPO/k6/script.js":/scripts/script.js:ro \
  grafana/k6:latest run --out influxdb=http://influxdb:8086/k6 /scripts/script.js

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — k6 Performance'"
echo "  datasource: InfluxDB-k6   (time range: Last 15 minutes)"
