#!/usr/bin/env bash
# Run the ShopLite Gatling (Java) simulation against this stack's mock, then
# stream its results into InfluxDB so the generic "ShopLite - Custom Listener
# (OK/KO)" dashboard fills in. Gatling has no per-sample InfluxDB output, so after
# the run we parse its simulation.log (tools/gatling_log_to_influx.py) into the
# OK/KO schema under the test name ShopLiteGatlingScala. The published gatling
# repo is left untouched. Open Grafana -> datasource "InfluxDB-custom".
#
#   ./tools/feed-gatling-scala.sh
#   VUS=40 CART_SIZE=12 ./tools/feed-gatling-scala.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATLING_REPO="${GATLING_REPO:-$ROOT/../ShopLite-load-tests-gatling-javaDSL}"
NET="${NET:-shoplite-observability_default}"
VUS="${VUS:-10}"; CART_SIZE="${CART_SIZE:-8}"; SIM="${SIM:-ShopLiteGatlingJava}"
IMG="shoplite-gatling-java"

cd "$ROOT"

[ -f "$GATLING_REPO/gatling/simulations/ShopLiteSimulation.java" ] || {
  echo "x gatling java repo not found at ${GATLING_REPO} - set GATLING_REPO=/path/to/ShopLite-load-tests-gatling-javaDSL"; exit 1; }

echo "-> ensuring InfluxDB + Grafana are up..."
docker compose up -d

echo "-> building + starting the ShopLite API mock on ${NET}..."
docker build -t shoplite-mock "$GATLING_REPO/mock" >/dev/null
docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true
if [ "${MOCK_FAIL_RATE:-0}" != "0" ]; then
  echo "   (chaos mock: failing ${MOCK_FAIL_RATE} of API requests)"
  docker run -d --name shoplite-mock-obs --network "$NET" --network-alias mock \
    -e FAIL_RATE="$MOCK_FAIL_RATE" -v "$ROOT/tools/chaos_mock.py":/chaos_mock.py:ro \
    python:3-alpine python /chaos_mock.py 8080 >/dev/null
else
  docker run -d --name shoplite-mock-obs --network "$NET" --network-alias mock shoplite-mock >/dev/null
fi

echo "-> building the Gatling (Java) image..."
docker build -t "$IMG" -f "$GATLING_REPO/gatling/Dockerfile" "$GATLING_REPO" >/dev/null

RES="$(mktemp -d)"
echo "-> running Gatling (Java) -> ${RES}..."
docker run --rm --network "$NET" \
  -e BASE_URL=http://mock:8080 -e CART_SIZE="$CART_SIZE" -e VUS="$VUS" \
  -v "$RES":/results "$IMG" \
  -rm local -s ShopLiteSimulation -rf /results -rd "ShopLite Gatling (Java) demo" \
  || echo "   (Gatling exited non-zero - e.g. failed assertions under chaos; parsing the log anyway)"

LOG="$(ls -t "$RES"/*/simulation.log | head -1)"
echo "-> parsing ${LOG} -> influxdb db custom (test ${SIM})..."
INFLUX_URL=http://localhost:8086 INFLUX_DB=custom python3 tools/gatling_log_to_influx.py "$LOG" "$SIM"

docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true
rm -rf "$RES"

echo
echo "Done. Open http://localhost:3000 -> ShopLite -> 'ShopLite - Custom Listener (OK/KO)'"
echo "  datasource: InfluxDB-custom   Test: ${SIM}   (time range: Last 15 minutes)"
