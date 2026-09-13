"""Self-contained Shamir secret sharing over a 256-bit prime (stdlib only).

Used by both the loopback ablation (threshold_ablation.py) and the Flask
multi-node simulator (flask_simulator/).
"""
import secrets

PRIME = 2**256 - 189  # a 256-bit prime (same size class as the paper's field)


def poly_eval(coeffs, x, p=PRIME):
    return sum(c * pow(x, i, p) for i, c in enumerate(coeffs)) % p


def split(secret, t, n, p=PRIME):
    """Split `secret` into n shares of a t-of-n scheme."""
    coeffs = [secret] + [secrets.randbelow(p) for _ in range(t - 1)]
    return [(i + 1, poly_eval(coeffs, i + 1, p)) for i in range(n)]


def recover(shares, p=PRIME):
    """Recover the secret from any t shares (Lagrange interpolation)."""
    s = 0
    for i, (xi, yi) in enumerate(shares):
        num = den = 1
        for j, (xj, _) in enumerate(shares):
            if i != j:
                num = num * (-xj) % p
                den = den * (xi - xj) % p
        s = (s + yi * num * pow(den, -1, p)) % p
    return s
