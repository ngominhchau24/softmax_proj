"""vec_dv_corner.py - vectors for tb/tb_smx_dv_corner.sv (called by model/gen_vectors.py).

Arithmetic corners that the REQ-VER-02 matrix of tb_smx_dv_ver02 does not single out. Each run
is named after its scenario; the testbench checks the shape of the rows and counts the bins.
  sum_min    the row sum at its lower bound 2^14, so Rcp = 2^26 uses all 27 bits (REQ-ARI-06):
             one element whose exponent sits just above -1, every other element so far below
             the maximum that its E is 0. This file asserts sum == 2^14 with the golden model.
  sum_max    the row sum at its upper bound 512 * 2^15 = 2^24 (REQ-ARI-05): K = 0 at L_MAX,
             asserted here as well
  dm_max     the largest possible jump of the running maximum, dM = 254: all -128 with one 127
             at K = 65535, the 127 placed in each group after the first, so the accumulated sum
             is shifted out completely at every point of the row
  len_sweep  every row length from 1 to L_MAX, one random row each, K rotating over corner and
             random values
Output: DIR/dv.hex, format in dv_common.py.
"""
import random

import softmax_ref as ref
from dv_common import DvWriter, L_MAX, R_MAX

K_ROT = [0, 1, 5909, 65535, 2, 255, 256, 32767, 32768, 65534]


def gen(args):
    P, n_seg = args.p, args.n_seg
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_corner P={P} N_SEG={n_seg} seed={args.seed}", P, n_seg)

    def row_sum(q, K):
        return ref.softmax_row(q, K, P=P, n_seg=n_seg)[1]["sum"]

    # ---- sum_min ----
    for q, K in ((1, 1), (-1, 65535), (2, 32769), (5, 13108)):
        assert row_sum([q], K) == 1 << 14, (q, K)
        w.add("sum_min", [[q]], K)
    for L in (2, P, P + 1, 2 * P + 1):
        rows = []
        for pos in sorted({0, L - 1, rng.randrange(L)}):
            r = [-128] * L
            r[pos] = 5
            assert row_sum(r, 13108) == 1 << 14, (L, pos)
            rows.append(r)
        w.add("sum_min", rows, 13108)

    # ---- sum_max ----
    rows = [[-128] * L_MAX, [127] * L_MAX, [rng.randint(-128, 127) for _ in range(L_MAX)]]
    assert all(row_sum(r, 0) == 1 << 24 for r in rows)
    w.add("sum_max", rows, 0)

    # ---- dm_max: the 127 in group g >= 1, first and last such group always included ----
    for L in (P + 1, 2 * P, 3 * P + 1, 64, L_MAX):
        G = (L + P - 1) // P
        groups = list(range(1, G))
        if len(groups) > R_MAX:
            step = (len(groups) - 1) / (R_MAX - 1)
            groups = sorted({groups[round(i * step)] for i in range(R_MAX)})
        rows = []
        for g in groups:
            r = [-128] * L
            r[g * P + rng.randrange(min(P, L - g * P))] = 127
            c = ref.softmax_row(r, 65535, P=P, n_seg=n_seg)[1]["c"]
            assert max(c) - min(c) == 254
            rows.append(r)
        w.add("dm_max", rows, 65535)

    # ---- len_sweep ----
    for L in range(1, L_MAX + 1):
        K = K_ROT[L % len(K_ROT)] if L % 2 else rng.randint(0, 65535)
        w.add("len_sweep", [[rng.randint(-128, 127) for _ in range(L)]], K)
    w.close()
