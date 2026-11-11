"""vec_dv_proto.py - vectors for tb/tb_smx_dv_proto.sv (called by model/gen_vectors.py).

Three runs, used in this order by the testbench:
  short  ends quickly; proves ERR clears and the core still works after the bad STARTs
  long   long enough to write an extra START at several BUSY cycles
  long2  long enough to hold a burst of writes and two reads while BUSY
Output: DIR/dv.hex, format in dv_common.py.
"""
import random

from dv_common import DvWriter


def gen(args):
    P = args.p
    rng = random.Random(args.seed)
    w = DvWriter(args.out, "dv.hex", f"dv_proto P={P} N_SEG={args.n_seg} seed={args.seed}",
                 P, args.n_seg)

    def rand_rows(L, R):
        return [[rng.randint(-128, 127) for _ in range(L)] for _ in range(R)]

    w.add("short", rand_rows(P + 1, 1), 5909)
    w.add("long", rand_rows(20 * P, 2), 5909)
    w.add("long2", rand_rows(24 * P + 3, 2), 40000)
    w.close()
