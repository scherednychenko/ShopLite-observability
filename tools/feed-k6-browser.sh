#!/usr/bin/env bash
# Run the ShopLite journey through a REAL Chromium via k6's browser module, so
# k6 collects Core Web Vitals (LCP / INP / CLS / FCP / TTFB) and streams them
# LIVE into this stack's InfluxDB (db "k6"). The
# "ShopLite — k6 Browser (Core Web Vitals)" dashboard then fills in.
#
#   ./tools/feed-k6-browser.sh                       # 8 iterations, fast storefront → green
#   ITERATIONS=15 ./tools/feed-k6-browser.sh
#   SLOW=1 DELAY_MS=2500 ./tools/feed-k6-browser.sh  # slow storefront → amber/red CWV
#
# This is the *frontend* counterpart to feed-k6.sh (which drives the JSON API at
# protocol level). It reuses the same static storefront as the sitespeed board,
# so CWV are measured on a real rendered page. Open Grafana → datasource
# "InfluxDB-k6". DEMO aid only — latencies are illustrative, not a real site.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UIPERF_REPO="${UIPERF_REPO:-$ROOT/../ShopLite-ui-perf}"
NET="${NET:-shoplite-observability_default}"
VUS="${VUS:-1}"; ITERATIONS="${ITERATIONS:-8}"

cd "$ROOT"

[ -d "$UIPERF_REPO/mock/html" ] || {
  echo "✖ ui-perf storefront not found at $UIPERF_REPO/mock/html — set UIPERF_REPO=/path/to/ShopLite-ui-perf"; exit 1; }

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ ensuring the k6+chromium image exists…"
docker image inspect shoplite-k6-browser >/dev/null 2>&1 || {
  echo "   building shoplite-k6-browser (k6 + Chromium)…"
  docker build -t shoplite-k6-browser -f tools/k6-browser.Dockerfile tools; }

echo "→ (re)starting the ShopLite storefront on the network ($NET) as 'mock'…"
docker rm -f shoplite-storefront-obs >/dev/null 2>&1 || true
if [ "${SLOW:-0}" != "0" ]; then
  echo "   (SLOW storefront: delaying ${DELAY_MS:-2500}ms/response → CWV breach Google thresholds)"
  docker run -d --name shoplite-storefront-obs --network "$NET" --network-alias mock \
    -e DELAY_MS="${DELAY_MS:-2500}" \
    -v "$UIPERF_REPO/mock/html":/site:ro -v "$ROOT/tools/slow_storefront.py":/slow_storefront.py:ro \
    -w /site python:3-alpine python /slow_storefront.py 80 >/dev/null
else
  docker image inspect shoplite-ui-perf-mock >/dev/null 2>&1 || \
    docker build -t shoplite-ui-perf-mock "$UIPERF_REPO/mock" >/dev/null
  docker run -d --name shoplite-storefront-obs --network "$NET" --network-alias mock shoplite-ui-perf-mock >/dev/null
fi

echo "→ running k6 browser ($VUS VU × $ITERATIONS iters) → influxdb:8086/k6…"
# --cap-add=SYS_ADMIN + no-sandbox let headless Chromium run in the container.
docker run --rm --network "$NET" --cap-add=SYS_ADMIN --shm-size=2g \
  -e K6_BROWSER_ARGS=no-sandbox -e BASE_URL=http://mock/ -e VUS="$VUS" -e ITERATIONS="$ITERATIONS" \
  -v "$ROOT/tools/k6-browser-cwv.js":/cwv.js:ro \
  shoplite-k6-browser run --out influxdb=http://influxdb:8086/k6 /cwv.js

docker rm -f shoplite-storefront-obs >/dev/null 2>&1 || true

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — k6 Browser (Core Web Vitals)'"
echo "  datasource: InfluxDB-k6   (Web Vitals: browser_web_vital_lcp / inp / cls / fcp / ttfb)"
