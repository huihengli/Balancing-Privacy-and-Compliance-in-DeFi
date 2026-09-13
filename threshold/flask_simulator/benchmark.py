"""Benchmark for the Flask multi-node threshold audit simulator.

Reproduces the paper's Table "Threshold Decryption Performance":
  - Key distribution time   (dealer -> n regulator nodes over HTTP, one-time)
  - Fragment exchange time  (combiner pulls t shares over HTTP, per trial)
  - Full decryption time    (exchange + Lagrange combine + AES-GCM decrypt)
  - Decryption success rate (t of n correct shares -> plaintext recovered)

Usage:  python benchmark.py [--trials 30] [--n 5] [--t 3] [--base-port 5100]
Output: flask_threshold_metrics.csv
"""
import argparse
import json
import os
import secrets
import statistics
import subprocess
import sys
import time
import urllib.request
from hashlib import sha256

from Crypto.Cipher import AES

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shamir  # noqa: E402

MSG = b"MINIMAL_AUDIT_INFO" * 4  # fixed-size audit plaintext


def http_json(method, url, payload=None, timeout=10):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def wait_healthy(url, retries=100):
    for _ in range(retries):
        try:
            if http_json("GET", url).get("ok"):
                return
        except Exception:
            time.sleep(0.1)
    raise RuntimeError(f"node at {url} did not become healthy")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=30)
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--t", type=int, default=3)
    ap.add_argument("--base-port", type=int, default=5100)
    args = ap.parse_args()

    ports = [args.base_port + i for i in range(args.n)]
    procs = []
    try:
        # ---- start n regulator nodes as separate Flask processes ----
        print(f"starting {args.n} regulator nodes on ports {ports} ...", flush=True)
        for i, port in enumerate(ports):
            procs.append(subprocess.Popen(
                [sys.executable, "node.py", str(i + 1), str(port)],
                cwd=HERE,
                stdout=open(os.path.join(HERE, f"node_{i+1}.out.log"), "w"),
                stderr=open(os.path.join(HERE, f"node_{i+1}.err.log"), "w")))
            print(f"  node {i+1} spawned (pid {procs[-1].pid}, poll {procs[-1].poll()})", flush=True)
        for port in ports:
            wait_healthy(f"http://127.0.0.1:{port}/health")
            print(f"  node on :{port} healthy", flush=True)

        # ---- key distribution (dealer -> n nodes, one-time) ----
        secret = secrets.randbelow(shamir.PRIME)
        key = sha256(secret.to_bytes(32, "big")).digest()
        nonce = os.urandom(12)
        ciphertext = nonce + AES.new(key, AES.MODE_GCM, nonce=nonce).encrypt(MSG)
        shares = shamir.split(secret, args.t, args.n)

        t0 = time.perf_counter()
        for (x, y), port in zip(shares, ports):
            http_json("POST", f"http://127.0.0.1:{port}/share", {"x": x, "y": y})
        key_dist_ms = (time.perf_counter() - t0) * 1000.0

        # ---- trials: fragment exchange + full decryption ----
        exchange_times, full_times, successes = [], [], 0
        for _ in range(args.trials):
            t0 = time.perf_counter()
            pulled = []
            for port in ports[: args.t]:  # first t nodes cooperate
                s = http_json("GET", f"http://127.0.0.1:{port}/share")
                pulled.append((s["x"], s["y"]))
            t1 = time.perf_counter()
            rec = shamir.recover(pulled)
            k = sha256(rec.to_bytes(32, "big")).digest()
            try:
                pt = AES.new(k, AES.MODE_GCM, nonce=ciphertext[:12]).decrypt(ciphertext[12:])
                successes += int(pt == MSG)
            except Exception:
                pass
            t2 = time.perf_counter()
            exchange_times.append((t1 - t0) * 1000.0)
            full_times.append((t2 - t0) * 1000.0)

        avg, sd = statistics.mean, statistics.stdev
        print("\n=== Threshold Decryption Performance (Flask multi-node simulator) ===")
        print(f"Key Distribution Time           : {key_dist_ms:.2f} ms")
        print(f"Average Fragment Exchange Time  : {avg(exchange_times):.2f} ± {sd(exchange_times):.2f} ms")
        print(f"Average Full Decryption Time    : {avg(full_times):.2f} ± {sd(full_times):.2f} ms")
        print(f"Decryption Success Rate         : {successes}/{args.trials} "
              f"({100 * successes / args.trials:.0f}%)")

        with open(os.path.join(HERE, "flask_threshold_metrics.csv"), "w", encoding="utf-8") as f:
            f.write("KeyDistributionMs,FragmentExchangeAvgMs,FragmentExchangeStdMs,"
                    "FullDecryptAvgMs,FullDecryptStdMs,SuccessRate\n")
            f.write(f"{key_dist_ms:.2f},{avg(exchange_times):.2f},{sd(exchange_times):.2f},"
                    f"{avg(full_times):.2f},{sd(full_times):.2f},{successes}/{args.trials}\n")
        print("Wrote flask_threshold_metrics.csv")
    finally:
        for p in procs:
            p.terminate()


if __name__ == "__main__":
    main()
