#!/usr/bin/env python3
"""svg2pdf.py - convert the design diagrams docs/spec/fig/*.svg to docs/figures/*.pdf for the report.

The SVG files are the source (drawn by the scripts next to them, docs/spec/09-diagram-rules.md);
the PDFs are generated and only exist because XeLaTeX cannot include SVG. Run this again after a
diagram changes. Usage (from the repo root):
    python3 docs/report/tools/svg2pdf.py [docs/spec/fig] [docs/figures]
Needs cairosvg (pip install cairosvg).
"""
import glob
import os
import sys

import cairosvg


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "docs/spec/fig"
    dst = sys.argv[2] if len(sys.argv) > 2 else "docs/figures"
    os.makedirs(dst, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(src, "*.svg"))):
        out = os.path.join(dst, os.path.basename(path)[:-4] + ".pdf")
        cairosvg.svg2pdf(url=path, write_to=out)
        print("wrote", out)


if __name__ == "__main__":
    main()
