#!/usr/bin/env python3
"""Plausible, varied service logs (seeded): timestamps, request ids, IPs,
latencies, JSON payloads and the odd stack trace. Unlike the synthetic
termbench corpus, lines rarely repeat, so compression results are realistic."""

import argparse
import random
import sys
import time
import uuid

p = argparse.ArgumentParser()
p.add_argument("--lines", type=int, default=0, help="0 = forever")
p.add_argument("--rate", type=float, default=0, help="lines per second, 0 = max")
args = p.parse_args()

rng = random.Random(7)
services = ["api", "auth", "billing", "sync", "relay", "worker", "scheduler"]
paths = ["/v1/vaults", "/v1/devices", "/v1/objects/{id}", "/v1/manifests", "/healthz", "/v1/push"]
levels = [("INFO", "32", 70), ("DEBUG", "2;37", 15), ("WARN", "33", 10), ("ERROR", "1;31", 5)]
weights = [w for *_, w in levels]
out = sys.stdout
t = 1_791_000_000.0
n = 0
while args.lines == 0 or n < args.lines:
    n += 1
    t += rng.expovariate(40)
    level, color, _ = rng.choices(levels, weights)[0]
    ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + f".{int(t * 1000) % 1000:03d}Z"
    rid = uuid.UUID(int=rng.getrandbits(128), version=4)
    ip = ".".join(str(rng.randint(1, 254)) for _ in range(4))
    path = rng.choice(paths).replace("{id}", f"{rng.getrandbits(48):012x}")
    status = rng.choices([200, 201, 204, 304, 400, 401, 404, 409, 429, 500, 503], [60, 8, 6, 5, 4, 3, 4, 2, 3, 3, 2])[0]
    ms = round(rng.lognormvariate(2.5, 0.9), 1)
    svc = rng.choice(services)
    line = (
        f"\x1b[90m{ts}\x1b[0m \x1b[{color}m{level:<5}\x1b[0m \x1b[36m{svc:<9}\x1b[0m "
        f"req={rid} ip={ip} {rng.choice(['GET', 'POST', 'PUT', 'DELETE'])} {path} "
        f"status=\x1b[{'32' if status < 400 else '31'}m{status}\x1b[0m latency={ms}ms"
    )
    if rng.random() < 0.15:
        line += f' body={{"device":"{rng.getrandbits(64):016x}","bytes":{rng.randint(0, 1 << 20)},"seq":{rng.randint(0, 99999)}}}'
    out.write(line + "\r\n")
    if level == "ERROR" and rng.random() < 0.3:
        for depth in range(rng.randint(3, 8)):
            out.write(f"    at {svc}.{rng.choice(['handle', 'decode', 'store', 'notify'])}_{depth} (src/{svc}/mod.rs:{rng.randint(10, 900)})\r\n")
    if args.rate > 0:
        out.flush()
        time.sleep(1 / args.rate)
out.flush()
