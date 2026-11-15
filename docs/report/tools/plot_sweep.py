#!/usr/bin/env python3
"""plot_sweep.py - chart of resources and Fmax against the lane count P (docs/figures/sweep_p.pdf).

The numbers are the Fitter results of docs/spec/03-design-spec.md section 7 (syn/fit.sh, Quartus
Prime Lite 18.1, 5CSXFC6D6F31C6, N_SEG = 8), the same ones as the sweep table of report chapter 7.
Update both when the design is fitted again. Usage (from the repo root):
    python3 docs/report/tools/plot_sweep.py [docs/figures]
Needs matplotlib.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

P = [4, 8, 16]
ALUT = [991, 1681, 2994]
REG = [860, 1211, 2011]
DSP = [12, 24, 48]
FMAX = {4: [148.81], 8: [122.09, 129.87, 134.41], 16: [108.57, 112.94, 107.83]}   # MHz, per seed
T_ROW = [310, 182, 118]                                                            # cycles, L = 512

INK, BLUE, GREY, RED = "#1a1a1a", "#1f5fa8", "#8a8a8a", "#b03a2e"


def main():
    dst = sys.argv[1] if len(sys.argv) > 1 else "docs/figures"
    plt.rcParams["font.family"] = ["DejaVu Sans"]
    plt.rcParams["pdf.fonttype"] = 42
    fig, ax = plt.subplots(1, 3, figsize=(6.3, 2.25))
    x = range(len(P))

    a = ax[0]
    w = 0.38
    a.bar([i - w / 2 for i in x], ALUT, w, color=BLUE, label="ALUT")
    a.bar([i + w / 2 for i in x], REG, w, color=GREY, label="Thanh ghi")
    for i in x:
        a.text(i - w / 2, ALUT[i] + 40, f"{ALUT[i]}", ha="center", va="bottom", fontsize=6)
        a.text(i + w / 2, REG[i] + 40, f"{REG[i]}", ha="center", va="bottom", fontsize=6)
    a.set_title("Tài nguyên logic", fontsize=8)
    a.set_ylim(0, 3500)
    a.legend(fontsize=6, frameon=False, loc="upper left")

    a = ax[1]
    for i, p in enumerate(P):
        a.scatter([i] * len(FMAX[p]), FMAX[p], s=14, color=BLUE, zorder=3)
        a.text(i + 0.12, min(FMAX[p]), f"{min(FMAX[p]):.0f}", fontsize=6, va="center")
    a.axhline(100, color=RED, lw=0.8, ls="--")
    a.text(len(P) - 0.55, 101.5, "mục tiêu 100 MHz", color=RED, fontsize=6, ha="right")
    a.set_title("Fmax theo từng seed (MHz)", fontsize=8)
    a.set_ylim(90, 160)
    a.set_xlim(-0.5, len(P) - 0.3)

    a = ax[2]
    a.bar(x, T_ROW, 0.5, color=BLUE)
    for i in x:
        a.text(i, T_ROW[i] + 4, f"{T_ROW[i]}", ha="center", va="bottom", fontsize=6)
    a.set_title("Chu kỳ mỗi hàng, L = 512", fontsize=8)
    a.set_ylim(0, 360)

    for a in ax:
        a.set_xticks(list(x))
        a.set_xticklabels([f"P = {p}" for p in P], fontsize=7)
        a.tick_params(axis="y", labelsize=6)
        for s in ("top", "right"):
            a.spines[s].set_visible(False)
    fig.tight_layout(pad=0.4, w_pad=1.0)
    out = os.path.join(dst, "sweep_p.pdf")
    fig.savefig(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
