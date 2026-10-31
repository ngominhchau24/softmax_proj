#!/usr/bin/env python3
"""
gen_vectors.py - test vector generator for the smx unit testbenches.

All arithmetic comes from model/softmax_ref.py (imported). This file only picks
stimulus and writes files; it must never re-implement the arithmetic.

Usage (from the repo root):
  python3 model/gen_vectors.py exp2 [--n-seg 8] [--out DIR] [--seed 1] [--t1-step 1]

exp2 writes DIR/t1.hex .. t4.hex (default DIR = tb/vectors/smx_exp2/n<N_SEG>),
test sets T1..T4 of docs/spec/blocks/smx_exp2.md section 8:
  t1  exhaustive d in [-17*2^16, 0], each d split into a random legal (u, M)
  t2  random (q, K, M) over the full legal range, with ~30 % bubbles (valid = 0)
  t3  corner cases
  t4  masked lanes (en = 0), any u and M including d > 0 -> E = 0
Line format, hex, two's complement at port width:  valid en u[24:0] m[8:0] e[15:0]
Lines starting with '#' are comments.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import softmax_ref as ref  # noqa: E402

U_W, C_W, E_W = 25, 9, 16            # must match rtl/pkg/smx_pkg.sv
K_MAX = (1 << ref.K_FRAC) - 1
U_MIN, U_MAX = -128 * K_MAX, 127 * K_MAX
M_MIN, M_MAX = ref.ceil_q16(U_MIN), ref.ceil_q16(U_MAX)   # -127, 127
ONE = 1 << ref.U_FRAC


def hexw(v, w):
    return f"{v & ((1 << w) - 1):0{(w + 3) // 4}x}"


class VecFile:
    def __init__(self, path, header):
        self.f = open(path, "w")
        self.f.write(f"# {header}\n# valid en u m e (hex)\n")
        self.n = 0

    def put(self, valid, en, u, m, e):
        self.f.write(f"{valid} {en} {hexw(u, U_W)} {hexw(m, C_W)} {hexw(e, E_W)}\n")
        self.n += 1

    def close(self):
        self.f.close()
        return self.n


def exp2_ref(u, m, n_seg, table):
    """Golden E for a legal lane: d = u - M*2^16 <= 0."""
    assert U_MIN <= u <= U_MAX and M_MIN <= m <= M_MAX and ref.ceil_q16(u) <= m
    return ref.exp2_neg(u - (m << ref.U_FRAC), n_seg, table)


def split_d(d, rng):
    """Random legal (u, M) with u - M*2^16 = d (d <= 0)."""
    lo = max(M_MIN, -((d - U_MIN) // ONE))      # ceil((U_MIN - d) / 2^16)
    hi = min(M_MAX, (U_MAX - d) // ONE)
    m = rng.randint(lo, hi)
    return d + m * ONE, m


def gen_exp2(n_seg, out, seed, t1_step):
    os.makedirs(out, exist_ok=True)
    rng = random.Random(seed)
    table = ref.pwl_table(n_seg)
    tag = f"smx_exp2 N_SEG={n_seg} seed={seed}"
    counts = {}

    # T1: exhaustive d, every F for each shift 0..15 plus the first cutoff band
    f = VecFile(os.path.join(out, "t1.hex"), f"{tag} set=t1 exhaustive step={t1_step}")
    for d in range(-17 * ONE, 1, t1_step):
        u, m = split_d(d, rng)
        f.put(1, 1, u, m, exp2_ref(u, m, n_seg, table))
    counts["t1"] = f.close()

    # T2: random q*K and M >= ceil(u), mixed with bubbles (handshake, T5)
    f = VecFile(os.path.join(out, "t2.hex"), f"{tag} set=t2 random")
    n_valid = 0
    while n_valid < 100000:
        if rng.random() < 0.3:
            f.put(0, rng.randint(0, 1), rng.randint(U_MIN, U_MAX), rng.randint(M_MIN, M_MAX), 0)
            continue
        u = rng.randint(-128, 127) * rng.randint(0, K_MAX)
        c = ref.ceil_q16(u)
        m = rng.randint(c, min(c + 16, M_MAX)) if rng.random() < 0.5 else rng.randint(c, M_MAX)
        f.put(1, 1, u, m, exp2_ref(u, m, n_seg, table))
        n_valid += 1
    counts["t2"] = f.close()

    # T3: corners
    f = VecFile(os.path.join(out, "t3.hex"), f"{tag} set=t3 corners")
    corners = [(0, 0), (-1, 0)]
    r_bits = ref.U_FRAC - (n_seg.bit_length() - 1)
    for idx in range(n_seg):                       # PWL segment edges, r = 0 and r = max
        for r in (0, (1 << r_bits) - 1):
            F = (idx << r_bits) | r
            for I in (-1, -2, -15, -16):
                corners.append(split_d(I * ONE + F, rng))
    for k in range(0, 18):                         # every shift amount, F = 0 and F = max
        corners.append(split_d(-k * ONE, rng))
        corners.append(split_d(-k * ONE - 1, rng))
    corners += [
        (U_MIN, M_MIN), (U_MIN, 0), (U_MIN, M_MAX),     # q = -128, K = 65535
        (U_MAX, M_MAX),                                 # q = 127,  K = 65535
        (-127 * ONE, M_MIN),                            # M = -127 reached exactly
        (0, 1), (0, 15), (0, 16), (0, M_MAX),           # K = 0 -> u = 0
    ]
    for u, m in corners:
        f.put(1, 1, u, m, exp2_ref(u, m, n_seg, table))
    counts["t3"] = f.close()

    # T4: masked lanes, garbage inputs (d > 0 allowed) -> E = 0
    f = VecFile(os.path.join(out, "t4.hex"), f"{tag} set=t4 masked")
    for _ in range(10000):
        f.put(1, 0, rng.randint(U_MIN, U_MAX), rng.randint(M_MIN, M_MAX), 0)
    counts["t4"] = f.close()

    print(f"wrote {out}: " + ", ".join(f"{k}={v}" for k, v in counts.items()))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="block", required=True)
    p = sub.add_parser("exp2", help="vectors for tb/tb_smx_exp2.sv")
    p.add_argument("--n-seg", type=int, default=8, choices=(4, 8, 16))
    p.add_argument("--out", default=None)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--t1-step", type=int, default=1,
                   help="stride over d in T1 (1 = exhaustive; larger = quick run)")
    a = ap.parse_args()
    if a.block == "exp2":
        gen_exp2(a.n_seg, a.out or f"tb/vectors/smx_exp2/n{a.n_seg}", a.seed, a.t1_step)
