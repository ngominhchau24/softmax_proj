#!/usr/bin/env python3
"""svg2pdf.py - convert the design diagrams the report uses from docs/spec/fig/*.svg to docs/figures/*.pdf.

The SVG files are the source (drawn by the scripts next to them, docs/spec/09-diagram-rules.md);
the PDFs are generated and only exist because XeLaTeX cannot include SVG. Run this again after a
diagram changes. Usage (from the repo root):
    python3 docs/report/tools/svg2pdf.py [docs/spec/fig] [docs/figures]
Needs cairosvg (pip install cairosvg).
"""
import os
import sys

import cairosvg

# the diagrams the report includes; add a name here when a chapter starts using another one
USED = ["smx_system", "softmax_flow", "smx_core", "smx_fsm", "smx_maxtree", "smx_exp2", "smx_sumacc"]


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "docs/spec/fig"
    dst = sys.argv[2] if len(sys.argv) > 2 else "docs/figures"
    os.makedirs(dst, exist_ok=True)
    for name in USED:
        path = os.path.join(src, name + ".svg")
        out = os.path.join(dst, name + ".pdf")
        cairosvg.svg2pdf(url=path, write_to=out)
        print("wrote", out)


if __name__ == "__main__":
    main()
