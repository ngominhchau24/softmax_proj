"""vec_scale.py - vectors for tb/tb_smx_scale.sv. All arithmetic comes from softmax_ref.

Line format (hex, two's complement at port width): valid q[7:0] k[15:0] u[24:0] c[8:0]
  t1  exhaustive: every q in [-128, 127] for a fixed list of K plus random K, back to back
  t2  random (q, K) with ~30 % bubbles (valid = 0, random garbage inputs)
  t3  corners: every (q, K) with u an exact multiple of 2^16 (c must not round up),
      K = 0, K = 65535, q = -128 / 127
"""
import os
import random

import softmax_ref as ref

Q_W, K_W, U_W, C_W = 8, 16, 25, 9      # must match rtl/pkg/smx_pkg.sv
K_MAX = (1 << K_W) - 1
FIXED_K = [0, 1, 2, 255, 256, 5909, 32767, 32768, 65534, 65535]


def hexw(v, w):
    return f"{v & ((1 << w) - 1):0{(w + 3) // 4}x}"


def expect(q, k):
    """Golden (u, c) of one element: u = q*K as in softmax_row, c = ceil_q16(u)."""
    u = q * k
    return u, ref.ceil_q16(u)


def put(f, valid, q, k):
    u, c = expect(q, k) if valid else (0, 0)
    f.write(f"{valid} {hexw(q, Q_W)} {hexw(k, K_W)} {hexw(u, U_W)} {hexw(c, C_W)}\n")


def gen(args):
    rng = random.Random(args.seed)
    counts = {}

    def open_set(name, what):
        f = open(os.path.join(args.out, name + ".hex"), "w")
        f.write(f"# smx_scale seed={args.seed} set={name} {what}\n# valid q k u c (hex)\n")
        return f

    # sanity: the per-element expectation agrees with softmax_row's own u and c
    for _ in range(20):
        k = rng.choice(FIXED_K + [rng.randint(0, K_MAX)])
        q = [rng.randint(-128, 127) for _ in range(32)]
        _, info = ref.softmax_row(q, k, P=args.p, n_seg=args.n_seg)
        assert info["u"] == [expect(v, k)[0] for v in q]
        assert info["c"] == [expect(v, k)[1] for v in q]

    f = open_set("t1", "every q for fixed and random K, back to back")
    ks = FIXED_K + [rng.randint(0, K_MAX) for _ in range(40)]
    n = 0
    for k in ks:
        for q in range(-128, 128):
            put(f, 1, q, k)
            n += 1
    f.close()
    counts["t1"] = n

    f = open_set("t2", "random with bubbles")
    n_valid = 0
    while n_valid < 100000:
        if rng.random() < 0.3:
            put(f, 0, rng.randint(-128, 127), rng.randint(0, K_MAX))
        else:
            put(f, 1, rng.randint(-128, 127), rng.randint(0, K_MAX))
            n_valid += 1
    f.close()
    counts["t2"] = n_valid

    f = open_set("t3", "exact multiples of 2^16, K and q extremes")
    n = 0
    n_neg = 0
    for k in range(0, K_MAX + 1, 256):          # u % 2^16 == 0 needs q*K divisible by 2^16
        for q in range(-128, 128):
            if (q * k) % (1 << 16) == 0:
                put(f, 1, q, k)
                n += 1
                if q * k < 0:
                    n_neg += 1
    for k in (0, 1, K_MAX - 1, K_MAX):
        for q in (-128, -127, -1, 0, 1, 126, 127):
            put(f, 1, q, k)
            n += 1
    assert n_neg > 0
    f.close()
    counts["t3"] = n
    print(f"wrote {args.out}: " + ", ".join(f"{k}={v}" for k, v in counts.items()))
