"""vec_core.py - vectors for tb/tb_smx_core.sv (called by model/gen_vectors.py).

All arithmetic is softmax_ref.softmax_row(q, K, P=args.p, n_seg=args.n_seg); this file only picks
rows and writes them. The output DIR/core.hex has this format ('#' lines are comments):

  NRUNS <n>                        first line that is not a comment: number of runs
  RUN <L> <R> <K> <flags>          decimal: row length, rows, SCALE_K, flag bits
  ROW <hex>                        R lines: L bytes of int8 input, element 0 first, 2 hex digits each
  Y <hex>                          R lines: L bytes of expected uint8 output, same layout

flags (decimal):
  bit 0  1 = leave X_BUF elements at i >= L unwritten (X in simulation, REQ-FUN-03); 0 = the
         testbench fills them with random garbage that includes 127 and -128
  bit 1  1 = after DONE start the same run again in the very next cycle, no gap (REQ-FUN-05)
  bit 2  1 = this run is the one the testbench aborts with reset in the middle of the run

The first run in the file always has bit 0 set and addresses that nothing wrote yet, so its
unwritten elements really are X. Coverage: REQ-VER-02 in full (L list, R = 1, 2, R_MAX,
K = 0, 1, 5909, 65535, all row kinds, L_MAX with R_MAX), plus random runs, plus repeats of earlier
cases (same rows, different history).
"""
import os
import random

import softmax_ref as ref

L_MAX, R_MAX = 512, 16               # must match rtl/pkg/smx_pkg.sv
K_LIST = [0, 1, 5909, 65535]

KIND_NAMES = ["all_min", "all_max", "uniform", "onehot_hi", "onehot_lo", "max_last_group",
              "ascending", "descending", "random_full", "random_narrow", "max_first_group",
              "max_last_elem"]


def make_row(kind, L, P, rng):
    G = (L + P - 1) // P
    last0 = (G - 1) * P
    if kind == 0:
        return [-128] * L
    if kind == 1:
        return [127] * L
    if kind == 2:
        return [rng.randint(-128, 127)] * L
    if kind == 3:
        r = [-128] * L
        r[rng.randrange(L)] = 127
        return r
    if kind == 4:
        r = [127] * L
        r[rng.randrange(L)] = -128
        return r
    if kind == 5:          # the row maximum appears only in the last group
        r = [rng.randint(-128, -2) for _ in range(L)]
        for i in range(last0, L):
            r[i] = rng.randint(-100, 60)
        r[rng.randrange(last0, L)] = rng.randint(61, 127)
        return r
    if kind == 6:
        return sorted(rng.randint(-128, 127) for _ in range(L))
    if kind == 7:
        return sorted((rng.randint(-128, 127) for _ in range(L)), reverse=True)
    if kind == 8:
        return [rng.randint(-128, 127) for _ in range(L)]
    if kind == 9:
        return [rng.randint(-8, 8) for _ in range(L)]
    if kind == 10:         # maximum in the first group, later groups never raise M
        r = [rng.randint(-128, 0) for _ in range(L)]
        r[rng.randrange(min(P, L))] = rng.randint(60, 127)
        return r
    r = [rng.randint(-128, 20) for _ in range(L)]      # maximum is the very last element
    r[L - 1] = 127
    return r


def make_rows(L, R, P, rng, base):
    rows = []
    for r in range(R):
        for attempt in range(60):
            kind = (base + r) % len(KIND_NAMES) if attempt == 0 else 8
            row = make_row(kind, L, P, rng)
            if row not in rows:
                break
        rows.append(row)
    return rows


class Writer:
    def __init__(self, path, tag):
        self.path, self.tag = path, tag
        self.runs = []
        self.n_elem = 0

    def add(self, rows, K, flags, P, n_seg):
        L = len(rows[0])
        ys = [ref.softmax_row(q, K, P=P, n_seg=n_seg)[0] for q in rows]
        self.runs.append((L, len(rows), K, flags, rows, ys))
        self.n_elem += L * len(rows)

    def close(self):
        with open(self.path, "w") as f:
            f.write(f"# {self.tag}\n# NRUNS n / RUN L R K flags / ROW hex x R / Y hex x R\n")
            f.write(f"NRUNS {len(self.runs)}\n")
            for L, R, K, flags, rows, ys in self.runs:
                f.write(f"RUN {L} {R} {K} {flags}\n")
                for q in rows:
                    f.write("ROW " + "".join(f"{v & 255:02x}" for v in q) + "\n")
                for y in ys:
                    f.write("Y " + "".join(f"{v:02x}" for v in y) + "\n")
        return len(self.runs), self.n_elem


def gen(args):
    P, n_seg, seed = args.p, args.n_seg, args.seed
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(seed)
    w = Writer(os.path.join(args.out, "core.hex"), f"smx_core P={P} N_SEG={n_seg} seed={seed}")
    base = [0]

    def add(L, R, K, flags=0):
        w.add(make_rows(L, R, P, rng, base[0]), K, flags, P, n_seg)
        base[0] += 3

    # fresh addresses first, so the unwritten elements are X (bit 0)
    add(P + 1, 1, 5909, 1)
    add(2 * P + 1, 3, 65535, 1)
    add(P - 1, 2, 1, 1)

    # REQ-VER-02 matrix: L list x K list, R = 2, every row kind appears
    Ls = sorted({1, P - 1, P, P + 1, 2 * P - 1, 2 * P + 1, L_MAX})
    idx = 0
    for L in Ls:
        for K in K_LIST:
            flags = 2 if idx % 4 == 0 else 0
            add(L, 2, K, flags)
            idx += 1

    # R = 1 for each L, R = R_MAX on a few lengths, L_MAX with R_MAX
    for L in Ls:
        add(L, 1, rng.choice(K_LIST + [rng.randint(2, 65534)]))
    for L, K in [(1, 5909), (P + 1, 1), (37, 65535), (128, 5909), (2 * P + 1, 0)]:
        add(L, R_MAX, K)
    add(L_MAX, R_MAX, 5909)
    add(L_MAX, R_MAX, 0)        # K = 0: all E equal, sum reaches its maximum 2^24
    add(L_MAX, R_MAX, 65535, 2)
    add(100, 3, 12345)

    # run selected for the reset test (bit 2): 8 groups, 2 rows
    add(8 * P, 2, 5909, 4)

    # repeats of earlier cases: same rows and K after other runs, REQ-FUN-05
    n_prev = len(w.runs)
    for pick in (3, 4, 9, 15, 25):
        if pick < n_prev:
            L, R, K, flags, rows, ys = w.runs[pick]
            w.add(rows, K, flags & 2, P, n_seg)

    # random runs
    for _ in range(24):
        L = rng.choice([rng.randint(1, 40), rng.randint(1, L_MAX), L_MAX - rng.randint(0, 3)])
        R = rng.choice([1, 2, 3, rng.randint(1, R_MAX)])
        K = rng.choice([rng.randint(0, 65535), rng.randint(0, 2000), rng.randint(60000, 65535)])
        add(L, R, K, rng.choice([0, 0, 2]))

    n, n_elem = w.close()
    print(f"smx_core P={P} N_SEG={n_seg}: {n} runs, {n_elem} elements")
