#!/usr/bin/env bash
# Run the k6 *business-operation* browser test (Login, Account Search) so it
# streams the per-operation timings + check results LIVE into this stack's
# InfluxDB (db "k6"), and the "ShopLite — Business Operations" dashboard fills in.
#
#   ./tools/feed-k6-business-ops.sh
#   ITERATIONS=12 ./tools/feed-k6-business-ops.sh
#
# This is the *business-facing* counterpart to the CWV boards: it reports named
# operation durations (`op_login_ms`, `op_account_search_ms`) and pass/fail
# `checks` — the "how long did logging in / searching take" stakeholders track,
# with CWV (feed-k6-browser.sh) underneath as diagnostics. The k6 script lives in
# the load-test repo and runs against public demo sites (no local mock needed).
# Open Grafana → datasource "InfluxDB-k6". DEMO aid only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K6_REPO="${K6_REPO:-$ROOT/../ShopLite-load-tests-k6}"
NET="${NET:-shoplite-observability_default}"
ITERATIONS="${ITERATIONS:-8}"

cd "$ROOT"

[ -f "$K6_REPO/k6/business-ops.js" ] || {
  echo "✖ business-ops.js not found at $K6_REPO/k6 — set K6_REPO=/path/to/ShopLite-load-tests-k6"; exit 1; }

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ ensuring the k6+chromium image exists…"
docker image inspect shoplite-k6-browser >/dev/null 2>&1 || {
  echo "   building shoplite-k6-browser (k6 + Chromium)…"
  docker build -t shoplite-k6-browser -f tools/k6-browser.Dockerfile tools; }

echo "→ running k6 business-ops ($ITERATIONS iterations) → influxdb:8086/k6…"
# --cap-add=SYS_ADMIN + no-sandbox let headless Chromium run in the container.
docker run --rm --network "$NET" --cap-add=SYS_ADMIN --shm-size=2g \
  -e K6_BROWSER_ARGS=no-sandbox -e ITERATIONS="$ITERATIONS" \
  -v "$K6_REPO/k6/business-ops.js":/business-ops.js:ro \
  shoplite-k6-browser run --out influxdb=http://influxdb:8086/k6 /business-ops.js

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — Business Operations'"
echo "  datasource: InfluxDB-k6   (op_login_ms / op_account_search_ms + checks)"
