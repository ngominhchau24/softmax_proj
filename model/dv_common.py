"""dv_common.py - shared helpers of the DV vector generators model/vec_dv_<test>.py.

All arithmetic is softmax_ref.softmax_row(q, K, P=..., n_seg=...); this file only writes runs.
The file format is read by tb/dv/smx_scoreboard.sv ('#' lines are comments):
  NRUNS <n>                 number of runs
  RUN <L> <R> <K> <name>    decimal row length, rows, SCALE_K; name has no spaces
  ROW <hex>                 R lines: L bytes of int8 input, element 0 first, 2 hex digits each
  Y <hex>                   R lines: L bytes of expected uint8 output, same layout
"""
import os

import softmax_ref as ref

L_MAX, R_MAX = 512, 16          # docs/requirements.md section 3


class DvWriter:
    def __init__(self, out_dir, fname, tag, p, n_seg):
        os.makedirs(out_dir, exist_ok=True)
        self.path = os.path.join(out_dir, fname)
        self.tag, self.p, self.n_seg = tag, p, n_seg
        self.runs = []
        self.n_elem = 0

    def add(self, name, rows, K):
        """One run: rows is a list of R lists of L int8 values."""
        L = len(rows[0])
        assert " " not in name and name
        assert 1 <= L <= L_MAX and 1 <= len(rows) <= R_MAX and 0 <= K <= 65535
        assert all(len(q) == L for q in rows)
        ys = [ref.softmax_row(q, K, P=self.p, n_seg=self.n_seg)[0] for q in rows]
        self.runs.append((L, len(rows), K, name, rows, ys))
        self.n_elem += L * len(rows)

    def close(self):
        with open(self.path, "w") as f:
            f.write(f"# {self.tag}\n# NRUNS n / RUN L R K name / ROW hex x R / Y hex x R\n")
            f.write(f"NRUNS {len(self.runs)}\n")
            for L, R, K, name, rows, ys in self.runs:
                f.write(f"RUN {L} {R} {K} {name}\n")
                for q in rows:
                    f.write("ROW " + "".join(f"{v & 255:02x}" for v in q) + "\n")
                for y in ys:
                    f.write("Y " + "".join(f"{v:02x}" for v in y) + "\n")
        print(f"{self.tag}: {len(self.runs)} runs, {self.n_elem} elements -> {self.path}")
