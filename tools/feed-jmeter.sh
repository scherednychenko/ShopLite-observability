#!/usr/bin/env bash
# Run the ShopLite JMeter scenario so it streams metrics LIVE into this stack's
# InfluxDB, and the "ShopLite — JMeter Performance" dashboard fills in.
#
#   ./tools/feed-jmeter.sh                 # defaults: 15 threads, 80s
#   THREADS=25 DURATION=180 ./tools/feed-jmeter.sh
#
# Why a script: the JMeter repo's own `docker compose up` is the standalone
# HTML-report demo — it has no InfluxDB and ships the Backend Listener DISABLED.
# This runs JMeter with the listener ENABLED, on THIS stack's network, pointed at
# influxdb:8086 (db "jmeter"). Open Grafana → datasource "InfluxDB" → measurement
# "ShopLite_Perf".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JMETER_REPO="${JMETER_REPO:-$ROOT/../ShopLite-load-tests}"
NET="${NET:-shoplite-observability_default}"
THREADS="${THREADS:-15}"; DURATION="${DURATION:-80}"; CART_SIZE="${CART_SIZE:-4}"

cd "$ROOT"

[ -f "$JMETER_REPO/jmeter/test-plans/ShopLite_Scenarios.jmx" ] || {
  echo "✖ JMeter repo not found at $JMETER_REPO — set JMETER_REPO=/path/to/ShopLite-load-tests"; exit 1; }
docker image inspect shoplite-jmeter >/dev/null 2>&1 || {
  echo "→ building shoplite-jmeter image…"; (cd "$JMETER_REPO" && docker compose build jmeter); }

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ ensuring the API mock is on the network ($NET)…"
docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true
docker run -d --name shoplite-mock-obs --network "$NET" --network-alias mock shoplite-mock >/dev/null

echo "→ enabling the Backend Listener (in a temp copy; published JMX untouched)…"
JMX="$(mktemp -t shoplite_jmx.XXXXXX).jmx"
python3 - "$JMETER_REPO/jmeter/test-plans/ShopLite_Scenarios.jmx" "$JMX" <<'PY'
import sys
src,dst=sys.argv[1],sys.argv[2]; t=open(src,encoding='utf-8').read()
n='<BackendListener guiclass="BackendListenerGui" testclass="BackendListener" testname="Backend Listener" enabled="false">'
t=t.replace(n,n.replace('enabled="false"','enabled="true"'),1)
t=t.replace('http://localhost:8086/write?db=jmeter','http://influxdb:8086/write?db=jmeter')
open(dst,'w',encoding='utf-8').write(t)
PY

echo "→ running JMeter ($THREADS threads, ${DURATION}s) → influxdb:8086/jmeter…"
docker run --rm --network "$NET" -v "$JMX":/test/jmeter/test-plans/ShopLite_Scenarios.jmx:ro \
  shoplite-jmeter \
  -n -t jmeter/test-plans/ShopLite_Scenarios.jmx -q jmeter/config/load_sanity.properties \
  -Jprotocol=http -Jhost=mock -Jport=8080 \
  -Jthreads="$THREADS" -JrampUpSec=10 -JdurationSec="$DURATION" -JcartSize="$CART_SIZE" \
  -JthinkTimeMinMs=80 -JthinkTimeRangeMs=250 \
  -l jmeter/results/feed.jtl
rm -f "$JMX"

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — JMeter Performance'"
echo "  datasource: InfluxDB   measurement: ShopLite_Perf   (time range: Last 15 minutes)"
