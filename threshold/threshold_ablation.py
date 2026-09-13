"""
方案 C3：无门限基线 vs (t,n) 门限协作解密的消融实验。

测量三种审计解密路径的耗时，用于回答"门限机制到底增加了多少成本"：
  (a) no-threshold  : 单一监管方直接持有完整密钥，AES-GCM 直接解密（基线）
  (b) threshold-local: 收集 t 个 Shamir 份额、本地拉格朗日重建后解密（无网络）
  (c) threshold-p2p : 模拟 Flask 多节点——t 个监管方经 loopback socket 交换
                      份额给合并方，合并重建后解密（含网络往返）

依赖：pip install pycryptodome   （AES-GCM；Shamir 为本文件自带实现，无其它依赖）
运行：python threshold_ablation.py
输出：threshold_ablation_summary.csv

说明：论文原模拟器（Flask + Shamir 库）测得的完整解密约 190.31±19.53 ms，
其中份额交换（188.29±20.04 ms）占主导。本脚本的 (c) 用裸 loopback socket，
网络成本更低，是"协作开销"的下界；若要与原 190ms 直接对比，把 (c) 换成你
的 Flask 模拟器路径即可——消融结论（门限的代价 = 份额交换 + 重建计算）不变。
"""
import os
import secrets
import socket
import statistics
import threading
import time
from hashlib import sha256

try:
    from Crypto.Cipher import AES
except ImportError:
    raise SystemExit("Missing pycryptodome. Run: pip install pycryptodome")

PRIME = 2**256 - 189          # 256-bit prime (same size class as the paper's field)
T, N = 3, 5                   # threshold t=3 of n=5 regulators
TRIALS = 30
MSG = b"MINIMAL_AUDIT_INFO" * 4   # fixed-size audit plaintext

# ---------------- self-contained Shamir ----------------
def poly_eval(coeffs, x, p=PRIME):
    return sum(c * pow(x, i, p) for i, c in enumerate(coeffs)) % p

def split(secret, t, n, p=PRIME):
    coeffs = [secret] + [secrets.randbelow(p) for _ in range(t - 1)]
    return [(i + 1, poly_eval(coeffs, i + 1, p)) for i in range(n)]

def recover(shares, p=PRIME):
    s = 0
    for i, (xi, yi) in enumerate(shares):
        num = den = 1
        for j, (xj, _) in enumerate(shares):
            if i != j:
                num = num * (-xj) % p
                den = den * (xi - xj) % p
        s = (s + yi * num * pow(den, -1, p)) % p
    return s

def key_from_secret(secret_int):
    return sha256(secret_int.to_bytes(32, "big")).digest()

def encrypt(key):
    nonce = os.urandom(12)
    return nonce + AES.new(key, AES.MODE_GCM, nonce=nonce).encrypt(MSG)

def decrypt(key, ct):
    return AES.new(key, AES.MODE_GCM, nonce=ct[:12]).decrypt(ct[12:])

def timeit(fn, trials=TRIALS):
    ts = []
    for _ in range(trials):
        t0 = time.perf_counter()
        fn()
        ts.append((time.perf_counter() - t0) * 1000.0)
    return statistics.mean(ts), statistics.stdev(ts) if len(ts) > 1 else 0.0

# ---------------- (c) loopback share exchange ----------------
def threshold_p2p_once(shares):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(T)
    port = srv.getsockname()[1]
    received = {}

    def server_loop():
        for _ in range(T):
            conn, _ = srv.accept()
            data = conn.recv(4096)
            xi, yi = data.decode().split(":")
            received[int(xi)] = int(yi)
            conn.close()
        srv.close()

    def send_share(xi, yi):
        c = socket.create_connection(("127.0.0.1", port), timeout=5)
        c.sendall(f"{xi}:{yi}".encode())
        c.close()

    st = threading.Thread(target=server_loop, daemon=True)
    st.start()
    holders = [threading.Thread(target=send_share, args=shares[i], daemon=True)
               for i in range(T)]
    for h in holders:
        h.start()
    st.join(timeout=5)
    for h in holders:
        h.join(timeout=5)
    return recover(list(received.items()))

# ---------------- experiment ----------------
def main():
    secret = secrets.randbelow(PRIME)
    key = key_from_secret(secret)
    ct = encrypt(key)
    shares = split(secret, T, N)

    # (a) no threshold
    a_avg, a_std = timeit(lambda: decrypt(key, ct))
    print(f"[no-threshold]   single-key AES-GCM decrypt           : {a_avg:8.4f} ± {a_std:8.4f} ms")

    # (b) threshold, local reconstruction
    b_avg, b_std = timeit(lambda: decrypt(key_from_secret(recover(shares[:T])), ct))
    print(f"[threshold]      t-of-n recover + decrypt (local)     : {b_avg:8.4f} ± {b_std:8.4f} ms")

    # (c) threshold, loopback share exchange
    def c_once():
        s = threshold_p2p_once(shares)
        decrypt(key_from_secret(s), ct)
    c_avg, c_std = timeit(c_once)
    print(f"[threshold]      t-of-n share exchange + decrypt (p2p): {c_avg:8.4f} ± {c_std:8.4f} ms")

    with open("threshold_ablation_summary.csv", "w", encoding="utf-8") as f:
        f.write("Path,Mean_ms,Stdev_ms\n")
        f.write(f"single-key,{a_avg:.4f},{a_std:.4f}\n")
        f.write(f"threshold-local,{b_avg:.4f},{b_std:.4f}\n")
        f.write(f"threshold-p2p,{c_avg:.4f},{c_std:.4f}\n")
    print("Saved threshold_ablation_summary.csv")

if __name__ == "__main__":
    main()
