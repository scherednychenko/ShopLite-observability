#!/usr/bin/env bash
# Run the ShopLite Locust scenario so it streams metrics LIVE into this stack's
# InfluxDB and fills the "ShopLite - Custom Listener (OK/KO)" dashboard. Locust
# has no native InfluxDB output, so we load a small extra locustfile
# (tools/locust_influx_listener.py) as a second -f; it writes the OK/KO schema
# that the generic custom board reads. Pick test "ShopLiteLocust" in the board.
#
#   ./tools/feed-locust.sh                          # 10 users, 120s
#   USERS=40 RUN_TIME=180s ./tools/feed-locust.sh
#
# Uses the official locustio/locust image on this stack's network, against the
# bundled mock. Open Grafana -> datasource "InfluxDB-custom".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCUST_REPO="${LOCUST_REPO:-$ROOT/../ShopLite-load-tests-locust}"
NET="${NET:-shoplite-observability_default}"
USERS="${USERS:-10}"; SPAWN_RATE="${SPAWN_RATE:-5}"; RUN_TIME="${RUN_TIME:-120s}"
CART_SIZE="${CART_SIZE:-8}"; SIM="${SIM:-ShopLiteLocust}"

cd "$ROOT"

[ -f "$LOCUST_REPO/locust/locustfile.py" ] || {
  echo "x locust repo not found at ${LOCUST_REPO} - set LOCUST_REPO=/path/to/ShopLite-load-tests-locust"; exit 1; }

echo "-> ensuring InfluxDB + Grafana are up..."
docker compose up -d

echo "-> building + starting the ShopLite API mock on ${NET}..."
docker build -t shoplite-mock "$LOCUST_REPO/mock" >/dev/null
docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true
docker run -d --name shoplite-mock-obs --network "$NET" --network-alias mock shoplite-mock >/dev/null

echo "-> running Locust (${USERS} users, ${RUN_TIME}) -> influxdb db custom (test ${SIM})..."
docker run --rm --network "$NET" \
  -e INFLUX_URL=http://influxdb:8086 -e INFLUX_DB=custom -e SIM="$SIM" -e CART_SIZE="$CART_SIZE" \
  -v "$LOCUST_REPO/locust":/mnt/locust:ro \
  -v "$ROOT/tools/locust_influx_listener.py":/mnt/locust_influx_listener.py:ro \
  locustio/locust:latest \
  -f /mnt/locust/locustfile.py,/mnt/locust_influx_listener.py \
  --headless --host http://mock:8080 \
  --users "$USERS" --spawn-rate "$SPAWN_RATE" --run-time "$RUN_TIME" --exit-code-on-error 0

docker rm -f shoplite-mock-obs >/dev/null 2>&1 || true

echo
echo "Done. Open http://localhost:3000 -> ShopLite -> 'ShopLite - Custom Listener (OK/KO)'"
echo "  datasource: InfluxDB-custom   Test: ${SIM}   (time range: Last 15 minutes)"
