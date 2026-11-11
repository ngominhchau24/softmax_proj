"""vec_dv_sanity.py - vectors for tb/tb_smx_dv_sanity.sv (called by model/gen_vectors.py).

A handful of ordinary runs that show the software sequence works end to end. The corner cases of
REQ-VER-02 belong to tb_smx_dv_ver02, not here. Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter, L_MAX, R_MAX

K_TYP = 5909        # mid-range K, the same value the designer's bench uses


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_sanity P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)

    def rand_rows(L, R, lo=-128, hi=127):
        return [[rng.randint(lo, hi) for _ in range(L)] for _ in range(R)]

    w.add("one_group", rand_rows(P, 1), K_TYP)                 # exactly one full group
    w.add("single_elem", rand_rows(1, 1), K_TYP)               # L = 1: y must saturate at 255
    w.add("partial_group", rand_rows(P + 1, 2), K_TYP)         # last group has one element
    w.add("two_groups", rand_rows(2 * P, 2, -20, 20), 20000)
    w.add("uniform", [[7] * 12], K_TYP)                        # all equal
    w.add("deit_row", rand_rows(197, 3, -40, 40), K_TYP)       # target workload: L = 197
    w.add("odd_len", rand_rows(37, 4), 65535)
    w.add("full_len", rand_rows(L_MAX, 2), K_TYP)              # L = L_MAX
    w.add("all_rows", rand_rows(3 * P + 2, R_MAX), 12345)      # R = R_MAX
    w.close()
