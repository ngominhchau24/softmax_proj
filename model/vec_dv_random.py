"""vec_dv_random.py - vectors for tb/tb_smx_dv_random.sv (called by model/gen_vectors.py).

Random runs for the given --seed: L and R drawn with a bias towards short rows, the group
boundaries and the maxima; K over the whole range with a bias to both ends; rows with wide,
narrow or mixed value ranges. Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter, L_MAX, R_MAX

N_RUNS = 60


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_random P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)

    for _ in range(N_RUNS):
        L = rng.choice([rng.randint(1, 3 * P), rng.randint(1, L_MAX), rng.randint(1, L_MAX),
                        P * rng.randint(1, L_MAX // P), L_MAX - rng.randint(0, 2)])
        R = rng.choice([1, 2, rng.randint(1, R_MAX), rng.randint(1, R_MAX), R_MAX])
        if L * R > 3000:                      # keep the test short: big jobs are rare
            R = max(1, 3000 // L) if rng.random() < 0.8 else R
        K = rng.choice([rng.randint(0, 65535), rng.randint(0, 65535), rng.randint(0, 300),
                        rng.randint(65000, 65535), 0, 1, 65535])
        rows = []
        for _ in range(R):
            style = rng.randrange(4)
            if style == 0:
                rows.append([rng.randint(-128, 127) for _ in range(L)])
            elif style == 1:
                c = rng.randint(-120, 120)
                rows.append([max(-128, min(127, c + rng.randint(-6, 6))) for _ in range(L)])
            elif style == 2:
                rows.append([rng.choice([-128, 127, 0, rng.randint(-128, 127)]) for _ in range(L)])
            else:
                base = [rng.randint(-128, -100)] * L
                for _ in range(rng.randint(1, 3)):
                    base[rng.randrange(L)] = rng.randint(90, 127)
                rows.append(base)
        w.add("random", rows, K)
    w.close()
