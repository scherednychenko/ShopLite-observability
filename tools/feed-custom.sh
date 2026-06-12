#!/usr/bin/env bash
# Populate the "ShopLite — Custom Listener (OK/KO)" dashboard with representative
# demo data. No off-the-shelf tool writes this exact schema (field response_time;
# tags status OK/KO, simulation, method, sampler_type, request_name; a "users"
# measurement for active VUs), so this generates a realistic OK/KO dataset and
# writes it straight to InfluxDB line protocol.
#
#   ./tools/feed-custom.sh                  # ~4 min window, ramp to 25 VUs, ~1.8% KO
#   WINDOW=600 PEAK_VUS=50 ./tools/feed-custom.sh
#
# Open Grafana → datasource "InfluxDB-custom" → Test "ShopLiteSimulation".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFLUX_URL="${INFLUX_URL:-http://localhost:8086}"
WINDOW="${WINDOW:-240}"; PEAK_VUS="${PEAK_VUS:-25}"

cd "$ROOT"

echo "→ ensuring InfluxDB + Grafana are up…"
docker compose up -d

echo "→ generating ${WINDOW}s of OK/KO demo data (peak ${PEAK_VUS} VUs) → custom db…"
WINDOW="$WINDOW" PEAK_VUS="$PEAK_VUS" INFLUX_URL="$INFLUX_URL" python3 - <<'PY'
import os, random, time, urllib.request
random.seed(11)
window=int(os.environ["WINDOW"]); peak=int(os.environ["PEAK_VUS"]); url=os.environ["INFLUX_URL"]
now=int(time.time()); start=now-window; ramp=min(30, window//6 or 1); SIM="ShopLiteSimulation"
reqs=[("Browse_Catalog","GET",90,40),("Add_To_Cart","POST",140,60),("Checkout_PlaceOrder","POST",210,90)]
lines=[]
for t in range(start, now+1):
    e=t-start
    vus = int(peak*e/ramp) if e<ramp else (int(peak*(window-e)/ramp) if e>window-ramp else peak)
    vus=max(0,vus); ts=t*1_000_000_000
    lines.append(f"users,test_type=default,env=demo,simulation={SIM},lg_id=lg1 active={vus}i {ts}")
    for _ in range(max(1,vus)//2):
        name,method,mu,sd=random.choice(reqs)
        ko=random.random()<0.018
        rt=max(5,int(random.gauss(mu*(2.4 if ko else 1.0),sd))); st="KO" if ko else "OK"
        lines.append(f"{SIM},test_type=default,env=demo,simulation={SIM},status={st},method={method},"
                     f"sampler_type=HTTP,request_name={name} response_time={rt}i {ts+random.randint(0,999_000_000)}")
req=urllib.request.Request(url+"/write?db=custom&precision=ns", data="\n".join(lines).encode(), method="POST")
print("  wrote", len(lines), "points, HTTP", urllib.request.urlopen(req).status)
PY

echo
echo "✓ Done. Open http://localhost:3000 → ShopLite → 'ShopLite — Custom Listener (OK/KO)'"
echo "  datasource: InfluxDB-custom   Test: ShopLiteSimulation   (time range: Last 15 minutes)"
