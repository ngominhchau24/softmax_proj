#!/usr/bin/env python3
"""dv_waves.py - waveform figures of the DV testcases for the report (docs/figures/dv_*.pdf).

Input: one VCD per DV test, dumped by the DV environment itself (tb/dv/smx_dv_env.sv, +VCD=...):
    cd sim && make run testname=tb_smx_dv_proto VCD=1      -> sim/wave/tb_smx_dv_proto_p8_n8.vcd
Usage (from the repo root):
    python3 docs/report/tools/dv_waves.py sim/wave [docs/figures]
A file may be named <test>.vcd or tb_smx_dv_<test>_p8_n8.vcd. Tests without a VCD are skipped.

Each figure shows the ports of smx_core around one event that the test is about. The window is
found from the signals themselves (first BUSY edge, first ERR edge, ...), not from fixed times.
Only the 11 port signals in the scope "env" are read, so a VCD with more signals is fine.
Needs matplotlib.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

CLK_PS = 10000                      # clock period of smx_dv_env: 10 ns
SIGS = ["clk", "rst_n", "acc_write", "acc_read", "acc_addr", "acc_byteenable", "acc_writedata",
        "acc_readdata", "status_busy", "status_done", "status_err"]
A_CTRL, A_STATUS, A_LEN, A_CYCLE = 0, 1, 2, 5


# ---------------------------------------------------------------------------------------------
# VCD reading
# ---------------------------------------------------------------------------------------------
def read_vcd(path, stop=None):
    """Return {signal: [(time_ps, value or None for X/Z), ...]} for the ports in scope 'env'.
    stop(sig) may return True to end the read early once enough of the file was seen."""
    ids, scope, scale = {}, [], 1
    sig = {s: [] for s in SIGS}
    t = 0
    n_since_check = 0
    with open(path, "r", errors="replace") as f:
        header = True
        for line in f:
            if header:
                w = line.split()
                if not w:
                    continue
                if w[0] == "$timescale":
                    txt = "".join(w[1:]).replace("$end", "") or next(f).strip()
                    num = int("".join(c for c in txt if c.isdigit()) or 1)
                    unit = "".join(c for c in txt if c.isalpha())
                    scale = num * {"ps": 1, "ns": 1000, "us": 10**6, "fs": 0.001}[unit]
                elif w[0] == "$scope":
                    scope.append(w[2])
                elif w[0] == "$upscope":
                    scope.pop()
                elif w[0] == "$var" and scope and scope[-1] == "env" and w[4] in sig:
                    ids.setdefault(w[3], []).append(w[4])
                elif w[0] == "$enddefinitions":
                    header = False
                continue
            c = line[0]
            if c == "#":
                t = int(int(line[1:]) * scale)
                n_since_check += 1
                if stop is not None and n_since_check >= 4000:
                    n_since_check = 0
                    if stop(sig):
                        break
            elif c in "01xXzZ":
                names = ids.get(line[1:].strip())
                if names:
                    v = int(c) if c in "01" else None
                    for n in names:
                        sig[n].append((t, v))
            elif c in "bB":
                bits, ident = line[1:].split()
                names = ids.get(ident)
                if names:
                    v = None if any(ch in "xXzZ" for ch in bits) else int(bits, 2)
                    for n in names:
                        sig[n].append((t, v))
    missing = [s for s in SIGS if not sig[s]]
    if missing:
        raise SystemExit(f"{path}: signals not found in scope env: {missing}")
    return sig


def value_at(tr, t):
    """Value of a transition list at time t (last change at or before t)."""
    lo, hi = 0, len(tr) - 1
    if tr[0][0] > t:
        return None
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if tr[mid][0] <= t:
            lo = mid
        else:
            hi = mid - 1
    return tr[lo][1]


def edges(tr, new):
    """Times where a 1-bit signal changes to 'new'."""
    return [t for i, (t, v) in enumerate(tr) if v == new and i > 0 and tr[i - 1][1] != new]


def cycles(sig, t_from, t_to):
    """Rising clock edges in [t_from, t_to]; signals are sampled just before each."""
    return [t for t in edges(sig["clk"], 1) if t_from <= t <= t_to]


def find_cycle(sig, cond, t_from=0, nth=1):
    """Time of the nth rising edge where cond(sample) holds; sample(name) = value before the edge."""
    n = 0
    for t in edges(sig["clk"], 1):
        if t < t_from:
            continue
        if cond(lambda name, t=t: value_at(sig[name], t - 1)):
            n += 1
            if n == nth:
                return t
    return None


# ---------------------------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------------------------
ROWS = [("clk", "clk", 1), ("rst_n", "rst_n", 1), ("acc_write", "acc_write", 1),
        ("acc_read", "acc_read", 1), ("acc_addr", "acc_addr", 4),
        ("acc_byteenable", "acc_byteenable", 1), ("acc_writedata", "acc_writedata", 8),
        ("acc_readdata", "acc_readdata", 8), ("status_busy", "status_busy", 1),
        ("status_done", "status_done", 1), ("status_err", "status_err", 1)]
BUS = {"acc_addr", "acc_byteenable", "acc_writedata", "acc_readdata"}
INK, SOFT, MARK = "#1a1a1a", "#8a8a8a", "#b03a2e"


def draw(sig, t0, t1, out, notes=(), spans=(), rows=None, width=6.3):
    """Draw [t0, t1] (ps). notes: (time_ps, row name), numbered 1, 2, ... in order.
    spans: (ta, tb, text) above the plot."""
    rows = [r for r in ROWS if rows is None or r[0] in rows]
    n = len(rows)
    h = 0.34
    fig, ax = plt.subplots(figsize=(width, 0.42 + h * n + (0.3 if spans else 0)))
    ncyc = (t1 - t0) / CLK_PS
    inch_per_cycle = width * (0.995 - 0.19) / ncyc

    def x(t):
        return (t - t0) / CLK_PS

    for k, (name, label, digits) in enumerate(rows):
        y = n - 1 - k
        tr = sig[name]
        pts = [(t0, value_at(tr, t0))] + [(t, v) for t, v in tr if t0 < t <= t1] + [(t1, None)]
        ax.text(-0.012 * ncyc, y + 0.3, label, ha="right", va="center", fontsize=7.5,
                family="monospace", color=INK)
        if name in BUS:
            for (ta, va), (tb, _) in zip(pts, pts[1:]):
                xa, xb = x(ta), x(tb)
                if xb - xa <= 0:
                    continue
                s = min(0.12, (xb - xa) / 2)
                col = MARK if va is None else INK
                ax.plot([xa, xa + s, xb - s, xb, xb - s, xa + s, xa],
                        [y + 0.3, y + 0.6, y + 0.6, y + 0.3, y, y, y + 0.3], color=col, lw=0.7)
                txt = "X" if va is None else f"{va:0{digits}X}"
                # largest font whose text fits between the slanted ends; none: leave it blank
                room = (xb - xa - 2 * s) * inch_per_cycle
                for fs in (6.0, 5.2, 4.5):
                    if len(txt) * fs * 0.62 / 72 <= room:
                        ax.text((xa + xb) / 2, y + 0.3, txt, ha="center", va="center",
                                fontsize=fs, family="monospace", color=col)
                        break
        else:
            xs, ys = [], []
            for (ta, va), (tb, _) in zip(pts, pts[1:]):
                lvl = y + (0.6 if va == 1 else 0.3 if va is None else 0.0)
                xs += [x(ta), x(tb)]
                ys += [lvl, lvl]
            ax.plot(xs, ys, color=INK, lw=0.8)

    # cycle grid at falling edges would hide the data; use light lines at rising edges
    first = next(t for t in edges(sig["clk"], 1) if t >= t0)
    step = 1 if ncyc <= 30 else 5 if ncyc <= 120 else 10
    k = 0
    t = first
    while t <= t1:
        if k % step == 0:
            ax.axvline(x(t), color=SOFT, lw=0.3, ls=":", zorder=0)
            ax.text(x(t), -0.45, str(k), ha="center", va="top", fontsize=6, color=SOFT)
        t += CLK_PS
        k += 1
    ax.text(ncyc / 2, -1.0, "chu kỳ clock", ha="center", va="top", fontsize=7, color=SOFT)

    # notes are numbered marks; the figure caption in the report says what each one shows
    names = [r[0] for r in rows]
    for k, (t, row) in enumerate(notes):
        y = n - 1 - names.index(row)
        ax.plot([x(t), x(t)], [y - 0.06, y + 0.66], color=MARK, lw=0.6)
        ax.text(x(t), y + 0.83, str(k + 1), ha="center", va="center", fontsize=5.5, color="white",
                bbox=dict(boxstyle="circle,pad=0.18", fc=MARK, ec=MARK, lw=0))
    for ta, tb, text in spans:
        ya = n + 0.25
        ax.annotate("", xy=(x(tb), ya), xytext=(x(ta), ya),
                    arrowprops=dict(arrowstyle="<->", color=MARK, lw=0.7))
        ax.text((x(ta) + x(tb)) / 2, ya + 0.12, text, ha="center", va="bottom", fontsize=7,
                color=MARK)

    ax.set_xlim(0, ncyc)
    ax.set_ylim(-1.5, n + (1.0 if spans else 0.5))
    ax.axis("off")
    fig.subplots_adjust(left=0.19, right=0.995, top=0.995, bottom=0.005)
    fig.savefig(out)
    plt.close(fig)
    print("wrote", out)


# ---------------------------------------------------------------------------------------------
# One figure per testcase: where to look
# ---------------------------------------------------------------------------------------------
def c(n):
    return n * CLK_PS


def start_write(s):
    return s("acc_write") == 1 and s("acc_addr") == A_CTRL and (s("acc_writedata") or 0) & 1


def fig_sanity(sig, out):
    """First run: START, the BUSY pulse, then STATUS, CYCLE_CNT and Y_BUF read with latency 2."""
    rise = edges(sig["status_busy"], 1)[0]
    fall = edges(sig["status_busy"], 0)[0]
    rd = find_cycle(sig, lambda s: s("acc_read") == 1, fall)
    draw(sig, rise - c(13), fall + c(12), out, rows=[r[0] for r in ROWS if r[0] != "rst_n"],
         notes=[(rise, "acc_write"), (rd + c(2.5), "acc_readdata")],
         spans=[(rise, fall, f"BUSY = {round((fall - rise) / CLK_PS)} chu kỳ")])


def fig_ver02(sig, out):
    """First run with a hostile tail: X_BUF words carry 7F, 80 past element L - 1 (L = 1)."""
    rise = edges(sig["status_busy"], 1)[0]
    w0 = find_cycle(sig, lambda s: s("acc_write") == 1 and (s("acc_addr") or 0) >= 0x800)
    draw(sig, w0 - c(1.5), rise + c(3.5), out,
         rows=["clk", "acc_write", "acc_addr", "acc_byteenable", "acc_writedata", "status_busy"],
         notes=[(w0, "acc_writedata"), (rise, "acc_write")])


def fig_proto_err(sig, out):
    """START with LEN = 0: DONE and ERR rise together, BUSY stays low."""
    rise = edges(sig["status_err"], 1)[0]
    draw(sig, rise - c(4.5), rise + c(9.5), out,
         rows=["clk", "acc_write", "acc_read", "acc_addr", "acc_writedata", "acc_readdata",
               "status_busy", "status_done", "status_err"],
         notes=[(rise, "acc_write"), (rise + c(0.5), "status_err")])


def fig_proto_busy(sig, out):
    """START written in the last BUSY cycle: ignored, BUSY falls and DONE rises as usual."""
    falls = edges(sig["status_busy"], 0)
    t = None
    for f in falls:                       # the START sampled at the edge where BUSY falls
        if start_write(lambda name, f=f: value_at(sig[name], f - 1)):
            t = f
            break
    if t is None:
        raise SystemExit("proto: no START in a last BUSY cycle found")
    draw(sig, t - c(6.5), t + c(8.5), out,
         rows=["clk", "acc_write", "acc_addr", "acc_writedata", "status_busy", "status_done",
               "status_err"],
         notes=[(t, "acc_write"), (t + c(0.5), "status_done")])


def fig_latency(sig, out):
    """Shortest run (L = 1, R = 1): BUSY lasts 2*1 + 54 + 1 cycles and CYCLE_CNT reads the same."""
    rise = edges(sig["status_busy"], 1)[0]
    fall = edges(sig["status_busy"], 0)[0]
    rd = find_cycle(sig, lambda s: s("acc_read") == 1 and s("acc_addr") == A_CYCLE, fall)
    n = round((fall - rise) / CLK_PS)
    draw(sig, rise - c(4), rd + c(5), out,
         rows=["clk", "acc_write", "acc_read", "acc_addr", "acc_readdata", "status_busy",
               "status_done"],
         notes=[(rd + c(2.5), "acc_readdata")],
         spans=[(rise, fall, f"BUSY = {n} chu kỳ = 2·1 + 54 + 1")])


def fig_reg(sig, out):
    """LEN written in full, then partly with byteenable = 0101, then read back."""
    t = find_cycle(sig, lambda s: s("acc_write") == 1 and s("acc_addr") == A_LEN
                   and s("acc_byteenable") == 0b0101)
    draw(sig, t - c(2.5), t + c(4.5), out,
         rows=["clk", "acc_write", "acc_read", "acc_addr", "acc_byteenable", "acc_writedata",
               "acc_readdata"],
         notes=[(t, "acc_byteenable"), (t + c(2.5), "acc_readdata")])


def fig_random(sig, out):
    """Asynchronous reset in the middle of a run: the status pins clear at once."""
    falls = [t for t in edges(sig["rst_n"], 0) if t > c(20)]
    t = falls[0]
    up = next(e for e in edges(sig["rst_n"], 1) if e > t)
    draw(sig, t - c(6.3), up + c(9), out,
         rows=["clk", "rst_n", "acc_write", "acc_read", "acc_addr", "acc_readdata", "status_busy",
               "status_done"],
         notes=[(t, "rst_n"), (t + c(0.2), "status_busy"), (up + c(3.5), "acc_readdata")])


FIGS = [("sanity", "dv_sanity_run", fig_sanity, None),
        ("ver02", "dv_ver02_tail", fig_ver02, None),
        ("proto", "dv_proto_err", fig_proto_err, None),
        ("proto", "dv_proto_start_busy", fig_proto_busy, None),
        ("latency", "dv_latency_cycle_cnt", fig_latency, None),
        ("reg", "dv_reg_byteenable", fig_reg, None),
        ("random", "dv_random_reset", fig_random, None)]


def stop_rule(test):
    """Stop reading a VCD once the events of its figures have passed."""
    if test == "random":
        def stop(sig):
            falls = [t for t in edges(sig["rst_n"], 0) if t > c(20)]
            ups = [t for t in edges(sig["rst_n"], 1) if falls and t > falls[0]]
            return bool(ups) and sig["clk"][-1][0] > ups[0] + c(40)
        return stop
    if test == "proto":
        return None                       # small file, the last event is near the end
    return lambda sig: len(edges(sig["status_busy"], 0)) >= 3


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else "docs/figures"
    os.makedirs(dst, exist_ok=True)
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["font.family"] = ["DejaVu Sans"]
    cache = {}
    for test, name, fn, _ in FIGS:
        path = next((p for p in (os.path.join(src, f"{test}.vcd"),
                                 os.path.join(src, f"tb_smx_dv_{test}_p8_n8.vcd"))
                     if os.path.exists(p)), None)
        if path is None:
            print(f"skip {name}: no VCD for {test} in {src}")
            continue
        if test not in cache:
            cache[test] = read_vcd(path, stop_rule(test))
        fn(cache[test], os.path.join(dst, name + ".pdf"))


if __name__ == "__main__":
    main()
