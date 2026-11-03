"""vec_norm.py - vectors for tb/tb_smx_norm.sv (called by model/gen_vectors.py).

All arithmetic is softmax_ref.norm_out; this file only picks (E, Rcp) pairs.
Line format, hex:  valid e[15:0] rcp[26:0] y[7:0]   ('#' lines are comments)
Sets:
  t1  corners: E and Rcp extremes, full cross product
  t2  independent random (E, Rcp) over full width, with bubbles
  t3  exact rounding boundary (E*Rcp mod 2^32 = 2^31-1, 2^31) and saturation
      boundary (rounded value 253..257)
  t4  reachable pairs from softmax_row(q, K, P, n_seg), incl. L = 1, with bubbles
"""
import os
import random

import softmax_ref as ref

E_W, RCP_W, Y_W = 16, 27, 8          # must match rtl/pkg/smx_pkg.sv
E_MAX, R_MAX = (1 << E_W) - 1, (1 << RCP_W) - 1
R_LO, R_HI = 1 << 16, 1 << 26        # reachable Rcp range: sum in [2^14, 2^24]
HALF = 1 << (ref.OUT_SHIFT - 1)
ONE32 = 1 << ref.OUT_SHIFT
N_RANGE = range(253, 258)            # rounded values around the 255 saturation point


class VecFile:
    def __init__(self, path, header):
        self.f = open(path, "w")
        self.f.write(f"# {header}\n# valid e rcp y (hex)\n")
        self.n = 0

    def put(self, e, rcp, valid=1):
        y = ref.norm_out(e, rcp) if valid else 0
        self.f.write(f"{valid} {e:04x} {rcp:07x} {y:02x}\n")
        self.n += 1

    def bubble(self, rng):
        self.put(rng.randint(0, E_MAX), rng.randint(0, R_MAX), 0)

    def close(self):
        self.f.close()
        return self.n


def boundary_pairs(rng, per_class):
    """Pairs with E*Rcp = n*2^32 + t exactly, t in {2^31-1, 2^31}, n in 253..257."""
    found = {}
    es = list(range(1, E_MAX + 1))
    rng.shuffle(es)
    for e in es:
        for n in N_RANGE:
            for t in (HALF - 1, HALF):
                prod = n * ONE32 + t
                if prod % e == 0 and prod // e <= R_MAX:
                    lst = found.setdefault((n, t), [])
                    if len(lst) < per_class:
                        lst.append((e, prod // e))
        if all(len(found.get((n, t), [])) >= per_class for n in N_RANGE for t in (HALF - 1, HALF)):
            break
    return found


def boundary_exact(rng, n, t, limit):
    """Exact (E, Rcp) with E*Rcp = n*2^32 + t, E in 1..65535."""
    prod = n * ONE32 + t
    out = []
    for e in rng.sample(range(1, E_MAX + 1), 4000):
        if prod % e == 0 and prod // e <= R_MAX:
            out.append((e, prod // e))
            if len(out) >= limit:
                break
    return out


def near_pairs(rng, n, t, tol, limit):
    """Pairs with |E*Rcp - (n*2^32 + t)| <= tol, for classes with no exact solution."""
    target = n * ONE32 + t
    out = []
    es = list(range(1, E_MAX + 1))
    rng.shuffle(es)
    for e in es:
        for r in (target // e, target // e + 1):
            if r <= R_MAX and abs(e * r - target) <= tol:
                out.append((e, r))
        if len(out) >= limit:
            break
    return out


def gen(args):
    out, seed = args.out, args.seed
    os.makedirs(out, exist_ok=True)
    rng = random.Random(seed)
    tag = f"smx_norm P={args.p} N_SEG={args.n_seg} seed={seed}"
    counts = {}

    # T1: corners, full cross product, back to back
    f = VecFile(os.path.join(out, "t1.hex"), f"{tag} set=t1 corners")
    es = [0, 1, 2, 255, 256, 32767, 32768, 32769, 65534, 65535]
    rs = [0, 1, 1 << 16, (1 << 16) + 1, 1 << 20, 1 << 26, (1 << 26) + 1,
          (1 << 27) - 2, (1 << 27) - 1]
    for e in es:
        for r in rs:
            f.put(e, r)
    for r in rs:                       # E = 0 must give y = 0 at any Rcp
        f.put(0, r)
    counts["t1"] = f.close()

    # T2: independent random pairs, full width, ~30 % bubbles
    f = VecFile(os.path.join(out, "t2.hex"), f"{tag} set=t2 random")
    n_valid = 0
    while n_valid < 100000:
        if rng.random() < 0.3:
            f.bubble(rng)
            continue
        mode = rng.random()
        if mode < 0.6:
            e, r = rng.randint(0, E_MAX), rng.randint(0, R_MAX)
        elif mode < 0.8:               # small products, rounding of low values
            e, r = rng.randint(0, E_MAX), rng.randint(0, 1 << 17)
        else:                          # reachable-like range
            e, r = rng.randint(0, 1 << 15), rng.randint(R_LO, R_HI)
        f.put(e, r)
        n_valid += 1
    counts["t2"] = f.close()

    # T3: rounding and saturation boundaries, plus one LSB of Rcp either side
    f = VecFile(os.path.join(out, "t3.hex"), f"{tag} set=t3 boundaries")
    found = boundary_pairs(rng, 60)
    for key in sorted(found):
        for e, r in found[key]:
            f.put(e, r)
            if r > 0:
                f.put(e, r - 1)
            if r < R_MAX:
                f.put(e, r + 1)
    # exact solutions for t = 2^31-1 (odd product) are rare; add exact ones at any n,
    # and near-misses (|diff| <= 64) at the saturation points
    for n in range(1, 2048):
        for e, r in boundary_exact(rng, n, HALF - 1, 4):
            f.put(e, r)
    for n in N_RANGE:
        for t in (HALF - 1, HALF):
            for e, r in near_pairs(rng, n, t, 64, 40):
                f.put(e, r)
    counts["t3"] = f.close()
    assert all((n, HALF) in found for n in N_RANGE), "boundary search"

    # T4: reachable pairs from the golden row model
    f = VecFile(os.path.join(out, "t4.hex"), f"{tag} set=t4 reachable")
    rows = 0
    while f.n < 60000:
        L = rng.choice([1, 1, 2, 3, 7, 8, 9, 16, 64, 100, 255, 512])
        K = rng.choice([0, 1, 5909, 65535, rng.randint(0, 65535), rng.randint(0, 65535)])
        mode = rng.random()
        if mode < 0.2:
            q = [rng.randint(-128, 127)] * L
        elif mode < 0.4:
            q = [rng.choice([-128, 127]) for _ in range(L)]
        else:
            q = [rng.randint(-128, 127) for _ in range(L)]
        _, info = ref.softmax_row(q, K, P=args.p, n_seg=args.n_seg)
        for e in info["E"]:
            if rng.random() < 0.15:
                f.bubble(rng)
            f.put(e, info["R"])
        rows += 1
    counts["t4"] = f.close()
    counts["t4_rows"] = rows

    print(f"wrote {out}: " + ", ".join(f"{k}={v}" for k, v in counts.items()))
