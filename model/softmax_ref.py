#!/usr/bin/env python3
"""
softmax_ref.py - Bit-exact golden reference model for the int8 softmax accelerator (smx).

This file is the SINGLE SOURCE OF TRUTH for the accelerator arithmetic.
docs/requirements.md section 4 describes the same algorithm in prose; if the two
ever disagree, fix the disagreement explicitly (update both + the decision log).

Algorithm summary (per row of L int8 elements, processed in groups of P):
  u_k   = q_k * K                         K: UQ0.16 (K = round(S_in*log2(e)*2^16))
  c_k   = ceil(u_k / 2^16)                IntMax operand (integer)
  pass 1, group by group (index order, elements >= L masked):
      Mg    = max(c_k in group)
      Mnew  = max(M, Mg)                  (M starts at -inf: first group sets it)
      sum   = (sum >> (Mnew - M)) + sum_k E(u_k - Mnew*2^16)
      M     = Mnew
  R     = floor(2^RECIP_SHIFT / sum)
  pass 2: y_k = min(255, (E(u_k - M*2^16) * R + 2^(OUT_SHIFT-1)) >> OUT_SHIFT)
  E(d)  : d <= 0 in Q.16 -> I = d >> 16 (floor), F = d & 0xFFFF,
          E = PWL(2^F) in UQ1.15, then >> (-I) ; 0 if -I > EXP_CUTOFF

Usage:
  python3 model/softmax_ref.py --selftest        # run built-in checks + accuracy sweep
  python3 model/softmax_ref.py --gen-pwl 8       # print PWL table (SystemVerilog localparams)
  python3 model/softmax_ref.py --gen-hex 8 rtl/pkg/pwl_n8.hex
"""
import argparse
import math
import sys

import numpy as np

# ---------------------------------------------------------------------------
# Fixed parameters (must match rtl/pkg/smx_pkg.sv and docs/requirements.md)
# ---------------------------------------------------------------------------
K_FRAC = 16          # K is UQ0.16
U_FRAC = 16          # u = q*K has 16 fractional bits
E_FRAC = 15          # E = 2^F in UQ1.15
EXP_CUTOFF = 15      # if -I > EXP_CUTOFF, E = 0  (E would be < 1 LSB anyway)
RECIP_SHIFT = 40     # R = floor(2^40 / sum)
OUT_SHIFT = 32       # y = (E*R + 2^31) >> 32  -> UINT8, scale 1/256
OUT_MAX = 255


def pwl_table(n_seg):
    """Chord (endpoint) PWL coefficients for 2^F on [0,1), UQ1.15.
    c[i] = round(2^(i/N) * 2^15), m[i] = round((2^((i+1)/N) - 2^(i/N)) * 2^15)."""
    assert n_seg in (4, 8, 16, 32)
    c = [round(2 ** (i / n_seg) * 2 ** E_FRAC) for i in range(n_seg)]
    m = [round((2 ** ((i + 1) / n_seg) - 2 ** (i / n_seg)) * 2 ** E_FRAC) for i in range(n_seg)]
    return c, m


def exp2_neg(d, n_seg, table=None):
    """E(d) for integer d <= 0 representing d / 2^16. Returns UQ1.15 integer (0..65535)."""
    assert d <= 0
    c, m = table if table is not None else pwl_table(n_seg)
    idx_bits = int(math.log2(n_seg))
    r_bits = U_FRAC - idx_bits
    I = d >> U_FRAC                 # floor (python >> is arithmetic)
    F = d & ((1 << U_FRAC) - 1)     # 0..65535
    idx = F >> r_bits
    r = F & ((1 << r_bits) - 1)
    E = c[idx] + ((m[idx] * r) >> r_bits)
    sh = -I
    if sh > EXP_CUTOFF:
        return 0
    return E >> sh


def ceil_q16(u):
    return -((-u) >> U_FRAC)        # ceil(u / 2^16) for python ints


def softmax_row(q, K, P=8, n_seg=8, trace=False):
    """Bit-exact model of one row. q: list/array of int8 (len L >= 1). K: 0..65535.
    Returns (y list of uint8, info dict)."""
    q = [int(v) for v in q]
    L = len(q)
    assert L >= 1 and 0 <= K < (1 << K_FRAC)
    assert all(-128 <= v <= 127 for v in q)
    table = pwl_table(n_seg)
    u = [v * K for v in q]
    c = [ceil_q16(x) for x in u]

    M = None
    s = 0
    for g0 in range(0, L, P):
        grp = range(g0, min(g0 + P, L))
        Mg = max(c[k] for k in grp)
        Mnew = Mg if M is None else max(M, Mg)
        if M is not None:
            s = s >> (Mnew - M)
        s += sum(exp2_neg(u[k] - (Mnew << U_FRAC), n_seg, table) for k in grp)
        M = Mnew
        if trace:
            print(f"group {g0 // P}: Mg={Mg} M={M} sum={s}")

    R = (1 << RECIP_SHIFT) // s
    y = []
    for k in range(L):
        e = exp2_neg(u[k] - (M << U_FRAC), n_seg, table)
        v = (e * R + (1 << (OUT_SHIFT - 1))) >> OUT_SHIFT
        y.append(min(OUT_MAX, v))
    return y, {"M": M, "sum": s, "R": R}


def k_from_scale(S):
    """HPS-side computation of the SCALE_K register."""
    K = round(S * math.log2(math.e) * (1 << K_FRAC))
    if not (0 < K < (1 << K_FRAC)):
        raise ValueError(f"S={S} gives K={K}, out of UQ0.16 range (need 0 < S < ~0.693)")
    return K


def softmax_float(q, S):
    x = np.asarray(q, dtype=np.float64) * S
    e = np.exp(x - x.max())
    return e / e.sum()


# ---------------------------------------------------------------------------
# Self test / accuracy sweep
# ---------------------------------------------------------------------------
def _accuracy(n_seg, S, L, trials, rng, P=8):
    K = k_from_scale(S)
    max_abs = 0.0
    mean_abs = 0.0
    for _ in range(trials):
        q = rng.integers(-128, 128, size=L)
        y, _ = softmax_row(q, K, P=P, n_seg=n_seg)
        ref = softmax_float(q, S)
        err = np.abs(np.asarray(y) / 256.0 - ref)
        max_abs = max(max_abs, err.max())
        mean_abs += err.mean()
    return max_abs, mean_abs / trials


def selftest():
    ok = True
    # 1. worked example from docs (S = 0.0625, q_max=40, q_i=20)
    K = k_from_scale(0.0625)
    assert K == 5909, K
    e_i = exp2_neg(20 * K - (4 << 16), 8)
    e_m = exp2_neg(40 * K - (4 << 16), 8)
    print(f"[example] K={K}  e_i={e_i / 2**15:.4f}  e_max={e_m / 2**15:.4f}  "
          f"ratio={e_i / e_m:.4f}  exp(-1.25)={math.exp(-1.25):.4f}")

    # 2. PWL relative error vs exact 2^F
    for n in (4, 8, 16):
        worst = 0.0
        for F in range(0, 1 << 16, 7):
            E = exp2_neg(F - (1 << 16), n) * 2   # d in [-1,0): E = 2^F / 2
            exact = 2 ** (F / 65536) * 2 ** E_FRAC
            worst = max(worst, abs(E - exact) / exact)
        print(f"[pwl] N_SEG={n:2d}  max rel err (incl. quantization) = {worst * 100:.3f}%")

    # 3. corner cases
    y, _ = softmax_row([5], K)                         # L = 1 -> saturates to 255
    ok &= y == [255]
    y, _ = softmax_row([0] * 512, K)                   # uniform -> 1/512 -> round(0.5) = 0 or 1
    ok &= len(set(y)) == 1
    y, _ = softmax_row([127] + [-128] * 511, 65535)    # one-hot extreme, max K
    ok &= y[0] == 255 and max(y[1:]) == 0
    y, _ = softmax_row([-128] * 8, 0)                  # K = 0 -> all equal
    ok &= len(set(y)) == 1
    # group-order dependence: same multiset, L not multiple of P
    y, info = softmax_row(list(range(-60, 60, 3)), K, trace=False)
    ok &= sum(y) in range(240, 260)
    print(f"[corner] all corner cases {'PASS' if ok else 'FAIL'}")

    # 4. accuracy sweep vs float softmax
    rng = np.random.default_rng(1)
    print("[accuracy] |y/256 - softmax_float|, random int8 rows")
    for S in (0.02, 0.0625, 0.2):
        for n in (4, 8, 16):
            mx, mean = _accuracy(n, S, 128, 30, rng)
            print(f"   S={S:<6} L=128 N_SEG={n:2d}  max={mx:.5f}  mean={mean:.6f}  (1 LSB = 0.00391)")
    return ok


def gen_pwl_sv(n):
    c, m = pwl_table(n)
    print(f"// Generated by model/softmax_ref.py --gen-pwl {n}. Do not edit by hand.")
    print(f"localparam logic [15:0] PWL_C_N{n} [{n}] = '{{" +
          ", ".join(f"16'd{v}" for v in c) + "};")
    print(f"localparam logic [15:0] PWL_M_N{n} [{n}] = '{{" +
          ", ".join(f"16'd{v}" for v in m) + "};")


def gen_hex(n, path):
    c, m = pwl_table(n)
    with open(path, "w") as f:
        for ci, mi in zip(c, m):
            f.write(f"{ci:04x}{mi:04x}\n")   # 32-bit word: [31:16]=c, [15:0]=m
    print(f"wrote {path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--gen-pwl", type=int)
    ap.add_argument("--gen-hex", nargs=2, metavar=("N_SEG", "PATH"))
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if a.gen_pwl:
        gen_pwl_sv(a.gen_pwl)
    if a.gen_hex:
        gen_hex(int(a.gen_hex[0]), a.gen_hex[1])
    if not (a.selftest or a.gen_pwl or a.gen_hex):
        ap.print_help()
