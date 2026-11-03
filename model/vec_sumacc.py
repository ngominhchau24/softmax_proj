"""
vec_sumacc.py - vectors for tb/tb_smx_sumacc.sv. All arithmetic comes from softmax_ref.

Line format (hex): valid first dm e[P*16-1:0] sum
  e has lane 0 in the low 16 bits. sum is the expected sum_out when this line
  leaves the pipe: the sum after every valid line up to and including this one
  (unchanged by a bubble; 0 before the first valid line, TB skips that check).
  Bubbles carry random first / dm / e, which must be ignored.
Sets:
  t1  random rows, back-to-back groups and rows
  t2  random rows, random bubbles between groups (gaps of 1..3 cycles)
  t3  K = 0, L = 512 (sum = 2^24) and L = 511 / 1 / P corners
  t5  short row, driven twice with a reset in flight in between
  t4  directed dm steps through group_sum: 0, 1, 23, 24, 25, 26, 31, 32, 254 on top of 2^24
"""
import os
import random
import softmax_ref as ref

E_MASK = 0xFFFF


def pad(e, P):
    return list(e) + [0] * (P - len(e))


def pack(e):
    v = 0
    for i, x in enumerate(e):
        v |= (x & E_MASK) << (16 * i)
    return v


class Stream:
    def __init__(self, path, P, header):
        self.f = open(path, "w")
        self.f.write(f"# {header}\n# valid first dm e sum (hex)\n")
        self.P = P
        self.sum = None
        self.n = 0     # valid groups

    def group(self, first, dm, e, s):
        """A valid group with expected sum s after it."""
        self.sum = s
        self.f.write(f"1 {int(first)} {dm:02x} {pack(pad(e, self.P)):0{self.P * 4}x} {s:07x}\n")
        self.n += 1

    def bubble(self, rng):
        e = [rng.randint(0, E_MASK) for _ in range(self.P)]
        s = "0000000" if self.sum is None else f"{self.sum:07x}"
        self.f.write(f"0 {rng.randint(0, 1)} {rng.randint(0, 255):02x} {pack(e):0{self.P * 4}x} {s}\n")

    def close(self):
        self.f.close()
        return self.n


def row_groups(q, K, P, n_seg):
    _, info = ref.softmax_row(q, K, P=P, n_seg=n_seg)
    return info["groups"]


def put_row(st, groups, rng=None, gap_prob=0.0):
    for i, g in enumerate(groups):
        if rng is not None:
            while rng.random() < gap_prob:
                st.bubble(rng)
        st.group(i == 0, g["dM"], g["E"], g["sum"])


def rand_row(rng, P):
    L = rng.choice([1, 2, P, P + 1, 3 * P, rng.randint(1, 512), rng.randint(1, 512), 512])
    L = min(L, 512)
    mode = rng.randint(0, 4)
    if mode == 0:     # uniform
        q = [rng.randint(-128, 127) for _ in range(L)]
        K = rng.randint(0, 65535)
    elif mode == 1:   # small spread, small K: E near 2^15, large sums
        q = [rng.randint(-3, 3) for _ in range(L)]
        K = rng.randint(0, 3000)
    elif mode == 2:   # ascending ramp, large K: dM > 0 nearly every group
        q = sorted(rng.randint(-128, 127) for _ in range(L))
        K = rng.randint(20000, 65535)
    elif mode == 3:   # one low group then a large peak: large dM
        q = [-128] * L
        q[rng.randrange(L)] = 127
        K = rng.randint(30000, 65535)
    else:             # constant
        q = [rng.randint(-128, 127)] * L
        K = rng.randint(0, 65535)
    return q, K


def gen(args):
    P, n_seg, out = args.p, args.n_seg, args.out
    os.makedirs(out, exist_ok=True)
    rng = random.Random(args.seed)
    tag = f"smx_sumacc P={P} N_SEG={n_seg} seed={args.seed}"
    counts = {}

    st = Stream(os.path.join(out, "t1.hex"), P, f"{tag} set=t1 back-to-back")
    for _ in range(150):
        q, K = rand_row(rng, P)
        put_row(st, row_groups(q, K, P, n_seg))
    counts["t1"] = st.close()

    st = Stream(os.path.join(out, "t2.hex"), P, f"{tag} set=t2 bubbles")
    for _ in range(150):
        q, K = rand_row(rng, P)
        put_row(st, row_groups(q, K, P, n_seg), rng, 0.3)
    counts["t2"] = st.close()

    st = Stream(os.path.join(out, "t3.hex"), P, f"{tag} set=t3 corners")
    for L in (512, 1, P, 511, 512):
        g = row_groups([0] * L, 0, P, n_seg)          # K = 0: u = 0, E = 2^15 each
        if L == 512:
            assert g[-1]["sum"] == 1 << 24
        put_row(st, g)
    q = [-128] * 512                                  # lowest first group, then peak at the end
    q[-1] = 127
    put_row(st, row_groups(q, 65535, P, n_seg))
    put_row(st, row_groups([127] * 512, 65535, P, n_seg))
    counts["t3"] = st.close()

    # t4: directed dm steps on top of a sum of exactly 2^24, expected from group_sum itself
    st = Stream(os.path.join(out, "t4.hex"), P, f"{tag} set=t4 dm steps")
    base = row_groups([0] * 512, 0, P, n_seg)
    for dm in (0, 1, 23, 24, 25, 26, 31, 32, 254):
        put_row(st, base)
        s = base[-1]["sum"]
        assert s == 1 << 24
        e = [rng.randint(0, 1 << 15) for _ in range(P)]
        s = ref.group_sum(s, dm, e, False)
        assert s < 1 << 25
        st.group(False, dm, e, s)
        e2 = [rng.randint(0, 1 << 15) for _ in range(P)]    # and one more step on top
        s = ref.group_sum(s, 0, e2, False)
        st.group(False, 0, e2, s)
    counts["t4"] = st.close()

    # t5: short row for the reset-in-flight test
    st = Stream(os.path.join(out, "t5.hex"), P, f"{tag} set=t5 reset test row")
    q = [-5, 3, 100, -128, 127, 0, 50, 60, 70, 80, 90, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] * 8
    put_row(st, row_groups(q, 40000, P, n_seg))
    counts["t5"] = st.close()

    print(f"wrote {out}: " + ", ".join(f"{k}={v}" for k, v in counts.items()))
