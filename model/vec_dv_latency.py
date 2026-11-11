"""vec_dv_latency.py - vectors for tb/tb_smx_dv_latency.sv (called by model/gen_vectors.py).

Shapes (L, R) chosen to move the group count one step at a time and to reach both ends:
every L from 1 to 2P+2, then lengths around larger group boundaries and L_MAX; R = 1 and 3 for
all of them, R = R_MAX for a few. Each shape appears with three kinds of data (all -128 with
K = 0, random with a mid-range K, one-hot with K = 65535), because the latency must depend on
L and R only. Runs of one shape are adjacent in the file.
Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter, L_MAX, R_MAX


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_latency P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)

    def shape(L, R):
        w.add("all_min_k0", [[-128] * L for _ in range(R)], 0)
        w.add("random", [[rng.randint(-128, 127) for _ in range(L)] for _ in range(R)], 5909)
        rows = []
        for _ in range(R):
            r = [-128] * L
            r[rng.randrange(L)] = 127
            rows.append(r)
        w.add("onehot_kmax", rows, 65535)

    Ls = list(range(1, 2 * P + 3)) + [3 * P, 197, 255, 256, 257, L_MAX - P, L_MAX - 1, L_MAX]
    for L in Ls:
        shape(L, 1)
        shape(L, 3)
    for L in (1, P + 1, 197, L_MAX):
        shape(L, R_MAX)
    w.close()
