"""
vec_maxtree.py - vectors for tb/tb_smx_maxtree.sv (docs/spec/blocks/smx_maxtree.md section 8).

Imported by gen_vectors.py, which calls gen(args) with args.p, args.n_seg, args.out, args.seed.
All numbers come from softmax_ref.softmax_row: c from info["c"], per-group Mg, M, dM from
info["groups"]. This file only builds rows, lays them out on the cycle timeline and writes files.

Output: DIR/t1.hex, one line per clock cycle (the stimulus and what the DUT must show LAT
cycles later):
    valid first en c m dm mk dk xm
  valid first   DUT inputs (first may be 1 while valid = 0: it must be ignored)
  en            P bits, lane 0 = bit 0
  c             P*9 bits, lane 0 in the low 9 bits; masked lanes carry random garbage
  m             expected m_out (9 bit two's complement) after this cycle's group
  dm            expected dm_out (8 bit), checked only when dk = 1
  mk            1 when m_out is defined (a first group has been seen since the file start)
  dk            1 when this cycle is a valid group (the only cycles where dm_out is defined)
  xm            0: keep garbage in masked lanes; 1: drive X in masked lanes; 2: X in half of them
Cycles with valid = 0 stand for gaps, and for pass 2 (long idle stretch with m held).
"""
import random

import softmax_ref as ref

C_W = 9


def _row_cases(P, rng):
    """List of (q list, K) covering the cases of section 8."""
    kmax = (1 << ref.K_FRAC) - 1
    rows = []
    lens = {1, 2, P - 1, P, P + 1, P + 2, 2 * P - 1, 2 * P, 2 * P + 1, 3 * P, 4 * P + 3, 512,
            511, 509, 256, 255, 64, 33, 17}
    lens = sorted(n for n in lens if 1 <= n <= 512)
    for L in lens:
        for _ in range(2):
            rows.append(([rng.randint(-128, 127) for _ in range(L)], rng.randint(1, kmax)))
        # max in the last group, last element only
        q = [rng.randint(-128, 0) for _ in range(L)]
        q[-1] = 127
        rows.append((q, kmax))
        # max in the first group only (M never rises afterwards)
        q = [rng.randint(-128, 0) for _ in range(L)]
        q[0] = 127
        rows.append((q, rng.randint(1, kmax)))
        # ascending: M rises in every group
        rows.append(([-128 + (255 * i) // max(L - 1, 1) for i in range(L)], kmax))
        # descending
        rows.append(([127 - (255 * i) // max(L - 1, 1) for i in range(L)], kmax))
        # K = 0: every c is 0
        rows.append(([rng.randint(-128, 127) for _ in range(L)], 0))
        # all equal, at the extremes
        rows.append(([-128] * L, kmax))
        rows.append(([127] * L, kmax))
    # largest dM: first group -127, second group 127 (dM = 254)
    rows.append(([-128] * P + [127], kmax))
    rows.append(([-128] * P + [127] * P, kmax))
    # smallest c after ceil: q = -128, K = 65535 gives c = -127, not -128
    rows.append(([-128] * (2 * P), kmax))
    # random lengths, random K
    for _ in range(300):
        L = rng.randint(1, 512)
        rows.append(([rng.randint(-128, 127) for _ in range(L)], rng.randint(0, kmax)))
    for _ in range(100):                   # small-range q, many equal maxima
        L = rng.randint(1, 4 * P + 1)
        rows.append(([rng.randint(-3, 3) for _ in range(L)], rng.randint(0, kmax)))
    rng.shuffle(rows)
    return rows


def gen(args):
    P, n_seg = args.p, args.n_seg
    rng = random.Random(args.seed)
    lines = []                                 # (valid, first, en, cvec, m, dm, mk, dk, xm)
    state = {"m": None}

    def hexw(v, w):
        return f"{v & ((1 << w) - 1):0{(w + 3) // 4}x}"

    def pack(c):
        v = 0
        for j, x in enumerate(c):
            v |= (x & ((1 << C_W) - 1)) << (C_W * j)
        return v

    def emit(valid, first, en, c, dm, xm):
        # c: P ints, masked lanes already filled with garbage
        mk = 0 if state["m"] is None else 1
        m = 0 if state["m"] is None else state["m"]
        lines.append(f"{valid} {first} {hexw(en, P)} {hexw(pack(c), P * C_W)} "
                     f"{hexw(m, C_W)} {hexw(dm, 8)} {mk} {valid} {xm}")

    def garbage_cycle():
        # a cycle with valid = 0: random first, en, c; nothing may change
        en = rng.getrandbits(P) | 1
        c = [rng.randint(-256, 255) for _ in range(P)]
        lines.append(f"0 {rng.getrandbits(1)} {hexw(en, P)} {hexw(pack(c), P * C_W)} "
                     f"{hexw(state['m'] or 0, C_W)} 00 {0 if state['m'] is None else 1} 0 "
                     f"{rng.choice([0, 1, 2])}")

    nrow = 0
    ngroups = 0
    for q, K in _row_cases(P, rng):
        y, info = ref.softmax_row(q, K, P=P, n_seg=n_seg)
        c_all = info["c"]
        L = len(q)
        gap_mode = rng.choice(["tight", "tight", "gaps"])
        for g, grp in enumerate(info["groups"]):
            lo = g * P
            n = min(P, L - lo)
            en = (1 << n) - 1
            c = [c_all[lo + j] if j < n else rng.randint(-256, 255) for j in range(P)]
            # lanes beyond L: sometimes the extreme values, to try to leak into the max
            if n < P and rng.random() < 0.5:
                for j in range(n, P):
                    c[j] = rng.choice([255, -256, 127, 0])
            state["m"] = grp["M"]
            emit(1, 1 if g == 0 else 0, en, c, grp["dM"], rng.choice([0, 1, 2]))
            ngroups += 1
            if gap_mode != "tight" and rng.random() < 0.4:
                for _ in range(rng.randint(1, 3)):
                    garbage_cycle()
        # between rows: a pass-2 stretch of idle cycles, or nothing at all (back-to-back rows)
        r = rng.random()
        if r < 0.5:
            for _ in range(rng.randint(1, 3 * P)):
                garbage_cycle()
        nrow += 1

    out = lines
    with open(f"{args.out}/t1.hex", "w") as f:
        f.write(f"# smx_maxtree P={P} n_seg={n_seg} seed={args.seed} rows={nrow} groups={ngroups}\n")
        f.write("# valid first en c m dm mk dk xm (hex)\n")
        f.write("\n".join(out) + "\n")
    print(f"wrote {args.out}: t1={len(out)} cycles, {ngroups} groups, {nrow} rows")
