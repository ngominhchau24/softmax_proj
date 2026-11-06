"""
vec_divider.py - vectors for tb/tb_smx_divider.sv (docs/spec/blocks/smx_divider.md section 8).

gen(args) is called by model/gen_vectors.py. The expected value of every sum comes from
softmax_ref.reciprocal; nothing is re-implemented here. The divider does not depend on P or
n_seg, so args.p and args.n_seg are accepted and ignored.

Files in args.out, one run per line, hex:  sum[24:0] rcp[26:0]
  t1  edges: both ends of the legal range, powers of two and neighbours, sums around
      2^40 / q for q = 2^j, 2^j +- 1 and alternating-bit patterns (quotient bit boundaries)
  t2  random: uniform over [2^14, 2^24] and log-uniform, --n-rand of each, interleaved
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import softmax_ref as ref  # noqa: E402

SUM_MIN, SUM_MAX = 1 << 14, 1 << 24      # legal range, REQ-ARI-06 / 05-cross-block.md 4.5


def add_args(p):
    p.add_argument("--n-rand", type=int, default=20000,
                   help="uniform and log-uniform random sums, each")


def _edges():
    s = set()
    # both ends, dense
    for d in range(0, 300):
        s.add(SUM_MIN + d)
        s.add(SUM_MAX - d)
    # powers of two and neighbours
    for k in range(14, 25):
        for d in range(-3, 4):
            s.add((1 << k) + d)
    # quotient bit boundaries: sums that put 2^40 / sum just around a given quotient
    qs = set()
    for j in range(0, 27):
        for d in (-2, -1, 0, 1, 2):
            qs.add((1 << j) + d)
    for pat in (0x2AAAAAA, 0x1555555, 0x3FFFFFF, 0x2000000, 0x1FFFFFF, 0x0AAAAAA,
                0x0555555, 0x3333333, 0x1999999, 0x0F0F0F0, 0x2492492):
        qs.add(pat)
    for q in qs:
        if q <= 0:
            continue
        base = (1 << ref.RECIP_SHIFT) // q
        for d in range(-2, 3):
            s.add(base + d)
    # all-ones and alternating patterns in the sum itself
    for k in range(15, 25):
        s.add((1 << k) - 1)
        s.add(int("10" * 13, 2) & ((1 << (k + 1)) - 1) | (1 << k))
    return sorted(x for x in s if SUM_MIN <= x <= SUM_MAX)


def gen(args):
    rng = random.Random(args.seed)
    tag = f"smx_divider seed={args.seed}"

    def put(f, s):
        assert SUM_MIN <= s <= SUM_MAX
        f.write(f"{s:07x} {ref.reciprocal(s):07x}\n")

    edges = _edges()
    with open(os.path.join(args.out, "t1.hex"), "w") as f:
        f.write(f"# {tag} set=t1 edges\n# sum rcp (hex)\n")
        for s in edges:
            put(f, s)
    n1 = len(edges)

    with open(os.path.join(args.out, "t2.hex"), "w") as f:
        f.write(f"# {tag} set=t2 random uniform + log-uniform\n# sum rcp (hex)\n")
        for _ in range(args.n_rand):
            put(f, rng.randint(SUM_MIN, SUM_MAX))
            e = rng.uniform(14.0, 24.0)
            put(f, min(SUM_MAX, max(SUM_MIN, int(2.0 ** e))))
    print(f"wrote {args.out}: t1={n1}, t2={2 * args.n_rand}")
