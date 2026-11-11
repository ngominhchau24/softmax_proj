"""vec_dv_reg.py - vectors for tb/tb_smx_dv_reg.sv (called by model/gen_vectors.py).

Rows that tell the byte lanes apart: a one-hot row for each element position of the first two
words and of a partial last word, so a swapped or shifted byte lane moves the 255 in Y, plus
ascending rows where every element is different. The testbench writes them one element at a
time through single byte enables (REQ-IF-03, REQ-IF-07).
Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter, R_MAX


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_reg P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)

    for L in (4, 7, 2 * P + 3):
        rows = []
        for pos in range(min(L, R_MAX)):
            r = [-128] * L
            r[pos] = 127
            rows.append(r)
        w.add(f"onehot_lanes_L{L}", rows, 65535)

    L = 2 * P + 2
    w.add("ascending", [[-60 + 3 * i for i in range(L)], [40 - 5 * i for i in range(L)]], 30000)
    w.add("random", [[rng.randint(-128, 127) for _ in range(37)] for _ in range(3)], 5909)
    w.close()
