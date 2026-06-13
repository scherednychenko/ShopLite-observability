#!/usr/bin/env bash
# Run the ShopLite sitespeed.io UI-performance journey so it streams Core Web
# Vitals LIVE into this stack's InfluxDB (Graphite line protocol on :2003,
# db "sitespeed"), and the "ShopLite — UI Performance (Core Web Vitals)"
# dashboard fills in.
#
#   ./tools/feed-sitespeed.sh                  # 5 iterations
#   ITERATIONS=10 ./tools/feed-sitespeed.sh
#
# Drives a real headless Chrome (the sitespeed.io image) over the static
# ShopLite storefront on this stack's network. Unlike the load tools (which use
# the InfluxDB HTTP API), sitespeed.io speaks Graphite, so InfluxDB ingests it on
# :2003 and the influxdb.conf templates map it to measurements/tags.
# Open Grafana → datasource "InfluxDB-sitespeed".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UIPERF_REPO="${UIPERF_REPO:-$ROOT/../ShopLite-ui-perf}"
NET="${NET:-shoplite-observability_default}"
ITERATIONS="${ITERATIONS:-5}"

cd "$ROOT"

[ -f "$UIPERF_REPO/sitespeed/scripts/shop-journey.js" ] || {
  echo "✖ ui-perf repo not found at $UIPERF_REPO — set UIPERF_REPO=/path/to/ShopLite-ui-perf"; exit 1; }

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ building + starting the ShopLite storefront mock on $NET…"
docker build -t shoplite-ui-perf-mock "$UIPERF_REPO/mock" >/dev/null
docker rm -f shoplite-storefront-obs >/dev/null 2>&1 || true
docker run -d --name shoplite-storefront-obs --network "$NET" --network-alias mock shoplite-ui-perf-mock >/dev/null

echo "→ running sitespeed.io ($ITERATIONS iterations) → influxdb:2003 (db sitespeed)…"
# config/shoplite.json already targets graphite host "influxdb" :2003 with the
# namespace the influxdb.conf templates expect, so it works unchanged here.
docker run --rm --network "$NET" --shm-size 2g --cap-add NET_ADMIN \
  -v "$UIPERF_REPO/sitespeed":/sitespeed -w /sitespeed \
  sitespeedio/sitespeed.io:41.3.3 \
  scripts/shop-journey.js --config config/shoplite.json --multi -n "$ITERATIONS" --outputFolder /tmp/ss

docker rm -f shoplite-storefront-obs >/dev/null 2>&1 || true

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — UI Performance (Core Web Vitals)'"
echo "  datasource: InfluxDB-sitespeed   (time range: Last 15 minutes)"
