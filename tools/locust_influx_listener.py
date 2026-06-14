"""
Locust -> InfluxDB listener for the ShopLite observability stack.

Loaded as an EXTRA locustfile (a second `-f`) so the published locust repo stays
untouched. It writes the SAME OK/KO schema the "ShopLite - Custom Listener (OK/KO)"
dashboard reads, so real Locust runs light up that generic board:

  measurement = <SIM>          field response_time (ms, int)
    tags: status (OK|KO), method, request_name, sampler_type=HTTP,
          simulation=<SIM>, test_type=default, env=demo
  measurement = users          field active (int)   tags: simulation=<SIM>, ...

Env:
  INFLUX_URL (default http://influxdb:8086), INFLUX_DB (default custom),
  SIM (default ShopLiteLocust)

Points are buffered and flushed once a second by a gevent greenlet (Locust runs
on gevent), plus a final flush on quit.
"""
import os
import time
import urllib.request

import gevent
from locust import events

INFLUX_URL = os.getenv("INFLUX_URL", "http://influxdb:8086")
INFLUX_DB = os.getenv("INFLUX_DB", "custom")
SIM = os.getenv("SIM", "ShopLiteLocust")

_buffer = []


def _flush():
    global _buffer
    if not _buffer:
        return
    payload = "\n".join(_buffer).encode()
    _buffer = []
    try:
        req = urllib.request.Request(
            f"{INFLUX_URL}/write?db={INFLUX_DB}&precision=ns",
            data=payload,
            method="POST",
        )
        urllib.request.urlopen(req, timeout=5)
    except Exception as exc:  # don't let telemetry break the test
        print(f"[influx-listener] write failed: {exc}")


@events.request.add_listener
def _on_request(request_type, name, response_time, response_length,
                exception, context, **kwargs):
    status = "KO" if exception else "OK"
    rt = int(response_time or 0)
    ts = time.time_ns()
    _buffer.append(
        f"{SIM},test_type=default,env=demo,simulation={SIM},status={status},"
        f"method={request_type},sampler_type=HTTP,request_name={name} "
        f"response_time={rt}i {ts}"
    )


@events.init.add_listener
def _on_init(environment, **kwargs):
    def _pump():
        while True:
            gevent.sleep(1)
            runner = getattr(environment, "runner", None)
            if runner is not None:
                _buffer.append(
                    f"users,test_type=default,env=demo,simulation={SIM},lg_id=lg1 "
                    f"active={runner.user_count}i {time.time_ns()}"
                )
            _flush()
    gevent.spawn(_pump)


@events.quit.add_listener
def _on_quit(**kwargs):
    _flush()
