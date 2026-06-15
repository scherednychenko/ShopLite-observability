#!/usr/bin/env bash
# Drive every ShopLite board into a visibly "unhealthy" state for demo
# screenshots, then leave the stack up. Nothing here is used in a normal run.
#
#  - API tools (JMeter, k6, Locust, Gatling x2) run against a chaos mock that
#    fails ~MOCK_FAIL_RATE of requests -> real errors / KO -> red panels.
#  - sitespeed runs on a throttled connection -> Core Web Vitals breach Google
#    thresholds -> amber/red gauges + table cells.
#
# Tools are expected to exit non-zero under chaos (k6 threshold breach, Gatling
# assertion failure, ...) - that is the point, so each is run tolerantly.
#
#   ./tools/demo-failures.sh
#   MOCK_FAIL_RATE=0.3 ./tools/demo-failures.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export MOCK_FAIL_RATE="${MOCK_FAIL_RATE:-0.2}"

run() {  # run "<label>" <command...> ; never aborts the orchestrator
  echo "===> $1"
  shift
  "$@" || echo "   (exited non-zero - expected under chaos, continuing)"
}

run "JMeter"           env THREADS=30 DURATION=120 ./tools/feed-jmeter.sh
run "k6"               env VUS=25 DURATION=120s ./tools/feed-k6.sh
run "Locust"           env USERS=20 RUN_TIME=90s ./tools/feed-locust.sh
run "Gatling (Scala)"  env VUS=20 ./tools/feed-gatling-scala.sh
run "Gatling (Java)"   env VUS=20 ./tools/feed-gatling-java.sh
run "sitespeed (slow)" env SLOW=1 ./tools/feed-sitespeed.sh

echo
echo "All boards fed. Open http://localhost:3000 -> ShopLite:"
echo "  JMeter / k6        -> error% / errors panels are red"
echo "  Custom (OK/KO)     -> pick ShopLiteLocust / ShopLiteGatlingScala / ShopLiteGatlingJava (KO is red)"
echo "  UI Performance     -> gauges + table cells amber/red (CWV over Google thresholds)"
