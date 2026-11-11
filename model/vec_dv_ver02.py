"""vec_dv_ver02.py - vectors for tb/tb_smx_dv_ver02.sv (called by model/gen_vectors.py).

The scenario list of REQ-VER-02. Every run holds rows of one kind, and the run name is that kind,
so the testbench can count which kind x length combinations were exercised:
  lengths  1, P-1, P, P+1, 2P+1, L_MAX
  K        0, 1, 65535, and one mid-range value
  kinds    all_min (-128), all_max (127), uniform, onehot_hi (one 127 among -128),
           onehot_lo (one -128 among 127), max_last_group (the row maximum appears only in the
           last group, so the running sum must be shifted at the very end), random
  rows     R = 2 in the matrix, then R = 1 and R = R_MAX for every length, and L_MAX with R_MAX
The testbench re-checks the kind of every row itself, so a wrong name here cannot fake coverage.
Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter, L_MAX, R_MAX

KINDS = ["all_min", "all_max", "uniform", "onehot_hi", "onehot_lo", "max_last_group", "random"]
K_LIST = [0, 1, 65535, 5909]


def applicable(kind, L, P):
    if kind in ("onehot_hi", "onehot_lo"):
        return L >= 2
    if kind == "max_last_group":
        return L > P                      # needs at least two groups
    return True


def make_row(kind, L, P, rng, pos=None):
    if kind == "all_min":
        return [-128] * L
    if kind == "all_max":
        return [127] * L
    if kind == "uniform":
        return [rng.randint(-127, 126)] * L
    if kind in ("onehot_hi", "onehot_lo"):
        lo, hi = (-128, 127) if kind == "onehot_hi" else (127, -128)
        r = [lo] * L
        r[rng.randrange(L) if pos is None else pos] = hi
        return r
    if kind == "max_last_group":
        last0 = ((L + P - 1) // P - 1) * P
        r = [rng.randint(-128, -2) for _ in range(L)]
        for i in range(last0, L):
            r[i] = rng.randint(-100, 60)
        r[rng.randrange(last0, L) if pos is None else pos] = rng.randint(61, 127)
        return r
    return [rng.randint(-128, 127) for _ in range(L)]


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_ver02 P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)
    Ls = [1, P - 1, P, P + 1, 2 * P + 1, L_MAX]

    # kind x length x K, two rows each; the first row puts its special element last
    for kind in KINDS:
        for L in Ls:
            if not applicable(kind, L, P):
                continue
            for K in K_LIST:
                w.add(kind, [make_row(kind, L, P, rng, pos=L - 1), make_row(kind, L, P, rng)], K)

    # R = 1 and R = R_MAX for every length
    for L in Ls:
        w.add("random", [make_row("random", L, P, rng)], rng.choice(K_LIST))
        w.add("random", [make_row("random", L, P, rng) for _ in range(R_MAX)], 5909)

    # the largest job: L_MAX with R_MAX at each corner K
    for K in (0, 1, 65535):
        w.add("random", [make_row("random", L_MAX, P, rng) for _ in range(R_MAX)], K)
    w.close()
