"""
Parse a Gatling simulation.log and write the ShopLite OK/KO schema into InfluxDB,
so a Gatling run lights up the generic "ShopLite - Custom Listener (OK/KO)"
dashboard (the same schema feed-custom.sh and the Locust listener use).

Gatling has no per-sample InfluxDB output; its native outputs are the HTML report
and simulation.log. So feed-gatling-*.sh runs Gatling, then this script parses the
log and pushes points. The published gatling repos are never modified.

Usage:
  python3 gatling_log_to_influx.py <path/to/simulation.log> [SIM_NAME]

Env:
  INFLUX_URL (default http://localhost:8086), INFLUX_DB (default custom)

simulation.log (Gatling 3.x) is tab-separated:
  RUN     | <class> | <id> | <epoch_ms> | <desc> | <version>
  USER    | <scenario> | START|END | <epoch_ms>
  REQUEST | <group> | <name> | <start_ms> | <end_ms> | OK|KO | <message>
"""
import os
import sys
import urllib.request

INFLUX_URL = os.getenv("INFLUX_URL", "http://localhost:8086")
INFLUX_DB = os.getenv("INFLUX_DB", "custom")

# The Gatling log doesn't record the HTTP verb; map it from the request name so
# the dashboard's `method` tag stays meaningful (matches the Locust/feed-custom).
METHOD = {
    "TX_Browse_Catalog": "GET",
    "TX_Add_To_Cart": "POST",
    "TX_Checkout_PlaceOrder": "POST",
}


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gatling_log_to_influx.py <simulation.log> [SIM_NAME]")
    log_path = sys.argv[1]
    sim = sys.argv[2] if len(sys.argv) > 2 else "ShopLiteGatling"

    requests = []        # (end_ms, name, status, response_time_ms)
    user_events = []     # (epoch_ms, +1 | -1)

    with open(log_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if p[0] == "REQUEST" and len(p) >= 6:
                name, start, end, status = p[2], int(p[3]), int(p[4]), p[5]
                requests.append((end, name, status, max(0, end - start)))
            elif p[0] == "USER" and len(p) >= 4:
                user_events.append((int(p[3]), 1 if p[2] == "START" else -1))

    lines = []
    for end_ms, name, status, rt in requests:
        method = METHOD.get(name, "HTTP")
        lines.append(
            f"{sim},test_type=default,env=demo,simulation={sim},status={status},"
            f"method={method},sampler_type=HTTP,request_name={name} "
            f"response_time={rt}i {end_ms * 1_000_000}"
        )

    # Active virtual users, sampled once per second from START/END events.
    if user_events:
        user_events.sort()
        first_sec = user_events[0][0] // 1000
        last_sec = user_events[-1][0] // 1000
        active, idx = 0, 0
        for sec in range(first_sec, last_sec + 1):
            upper_ms = (sec + 1) * 1000
            while idx < len(user_events) and user_events[idx][0] < upper_ms:
                active += user_events[idx][1]
                idx += 1
            lines.append(
                f"users,test_type=default,env=demo,simulation={sim},lg_id=lg1 "
                f"active={max(0, active)}i {sec * 1000 * 1_000_000}"
            )

    written = 0
    for i in range(0, len(lines), 5000):
        chunk = "\n".join(lines[i:i + 5000]).encode()
        req = urllib.request.Request(
            f"{INFLUX_URL}/write?db={INFLUX_DB}&precision=ns", data=chunk, method="POST")
        urllib.request.urlopen(req, timeout=10)
        written += len(lines[i:i + 5000])

    print(f"wrote {written} points to db '{INFLUX_DB}' (sim={sim}) "
          f"from {log_path} [{len(requests)} requests]")


if __name__ == "__main__":
    main()
