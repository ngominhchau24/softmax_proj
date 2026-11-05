"""schematic.py - hand-placed block diagrams as SVG, rules in docs/spec/diagram-rules.md.

A figure is a small Python file next to this one: it creates a Sheet, places boxes, routes wires by
explicit points, and calls save(). save() refuses to write a figure that breaks a checkable rule:
a wire that is not horizontal or vertical, a wire through a box, two wires running on top of each
other, an arrow that stops in empty space, a label on top of a wire or box, or a point off the
10 px grid.

    python3 docs/spec/fig/<figure>.py      # writes docs/spec/fig/<figure>.svg
"""
import os
import sys
from xml.sax.saxutils import escape

FONT = "Arial, Helvetica, sans-serif"
GRID = 10
SIZE_BOX, SIZE_SUB, SIZE_NET = 13, 11, 11
CHAR_W = 0.5        # estimated average character width, as a fraction of the font size
STROKE_BOX, STROKE_WIRE, STROKE_BUS = 1.5, 1.2, 2.4


class Sheet:
    def __init__(self, name, width, height):
        self.name, self.w, self.h = name, width, height
        self.items, self.boxes, self.segs, self.errors, self.labels = [], [], [], [], []
        self.pins = set()
        self.borders = []

    def _grid(self, *vals):
        for v in vals:
            if v % GRID:
                self.errors.append(f"{v} is off the {GRID} px grid")

    def _text(self, x, y, s, size=SIZE_NET, anchor="start"):
        self.items.append(f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}">{escape(s)}</text>')

    def box(self, x, y, w, h, name, sub=None):
        """A block: square corners, white fill, name centered, optional second line."""
        self._grid(x, y, w, h)
        self.boxes.append((x, y, w, h, name))
        self.items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#fff" '
                          f'stroke="#000" stroke-width="{STROKE_BOX}"/>')
        cx, cy = x + w // 2, y + h // 2
        if sub:
            self._text(cx, cy - 3, name, SIZE_BOX, "middle")
            self._text(cx, cy + 13, sub, SIZE_SUB, "middle")
        else:
            self._text(cx, cy + 4, name, SIZE_BOX, "middle")

    def boundary(self, x, y, w, h, name):
        """A hierarchy boundary: dashed, name inside at the bottom left."""
        self._grid(x, y, w, h)
        self.items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="#000" '
                          f'stroke-width="{STROKE_WIRE}" stroke-dasharray="7 4"/>')
        self.borders.append((x, y, w, h))
        self._text(x + 8, y + h - 8, name, SIZE_SUB)

    def _label(self, x, y, s, anchor="start"):
        """Text outside any box. Its bounding box is estimated and checked against wires and boxes."""
        w = len(s) * SIZE_NET * CHAR_W
        x0 = x - w if anchor == "end" else x
        self.labels.append((x0, y - SIZE_NET + 2, x0 + w, y + 2, s))
        self._text(x, y, s, SIZE_NET, anchor)

    def wire(self, pts, label=None, at=None, bus=False, arrow=True, side="auto", lx=None, port=False):
        """A net through explicit points. The arrow goes on the last point only.
        label sits above a horizontal segment or right of a vertical one, on segment index `at`.
        lx moves the label along a horizontal segment to that x.
        port=True marks the last point as an output pin of the figure, so it may end in empty space."""
        self._grid(*[c for p in pts for c in p])
        for a, b in zip(pts, pts[1:]):
            if a[0] != b[0] and a[1] != b[1]:
                self.errors.append(f"diagonal wire {a} -> {b} ({label})")
            if a == b:
                self.errors.append(f"zero-length wire at {a} ({label})")
            self.segs.append((a, b, label))
        d = " ".join(f"{x},{y}" for x, y in pts)
        marker = ' marker-end="url(#arrow)"' if arrow else ""
        width = STROKE_BUS if bus else STROKE_WIRE
        self.items.append(f'<polyline points="{d}" fill="none" stroke="#000" stroke-width="{width}"{marker}/>')
        if arrow and not port:
            self.pins.add(pts[-1])
        if label:
            i = at if at is not None else 0
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            if y0 == y1:
                ax = lx if lx is not None else min(x0, x1) + 5
                self._label(ax, y0 - 5 if side != "below" else y0 + 14, label)
            else:
                ay = (y0 + y1) // 2 + 4
                if side == "left":
                    self._label(x0 - 5, ay, label, "end")
                else:
                    self._label(x0 + 5, ay, label)

    def dot(self, x, y):
        """A junction. Wires that cross without a dot are not connected."""
        self._grid(x, y)
        self.items.append(f'<circle cx="{x}" cy="{y}" r="2.8" fill="#000"/>')
        self.dots = getattr(self, "dots", set()) | {(x, y)}

    def note(self, x, y, s):
        self._label(x, y, s)

    def _check(self, allow_free_ends):
        for a, b, label in self.segs:
            lo = (min(a[0], b[0]), min(a[1], b[1]))
            hi = (max(a[0], b[0]), max(a[1], b[1]))
            for x, y, w, h, name in self.boxes:
                if lo[0] < x + w and hi[0] > x and lo[1] < y + h and hi[1] > y:
                    self.errors.append(f"wire {label} {a}->{b} goes through {name}")
        horiz = [s for s in self.segs if s[0][1] == s[1][1]]
        vert = [s for s in self.segs if s[0][0] == s[1][0]]
        for group, fix, run in ((horiz, 1, 0), (vert, 0, 1)):
            for i, s in enumerate(group):
                for t in group[i + 1:]:
                    if s[0][fix] != t[0][fix]:
                        continue
                    a0, a1 = sorted((s[0][run], s[1][run]))
                    b0, b1 = sorted((t[0][run], t[1][run]))
                    if a0 < b1 and b0 < a1 and s[2] != t[2]:
                        self.errors.append(f"wires {s[2]} and {t[2]} overlap at {s[0]}..{t[1]}")
        for x0, y0, x1, y1, text in self.labels:
            for a, b, label in self.segs:
                if (min(a[0], b[0]) < x1 and max(a[0], b[0]) > x0
                        and min(a[1], b[1]) < y1 and max(a[1], b[1]) > y0):
                    self.errors.append(f"label '{text}' lies on wire {label} {a}->{b}")
            for x, y, w, h, name in self.boxes:
                if x < x1 and x + w > x0 and y < y1 and y + h > y0:
                    self.errors.append(f"label '{text}' lies on box {name}")
            for x, y, w, h in self.borders:
                if (y < y1 and y + h > y0 and (x0 < x < x1 or x0 < x + w < x1)) or (
                        x < x1 and x + w > x0 and (y0 < y < y1 or y0 < y + h < y1)):
                    self.errors.append(f"label '{text}' lies on the boundary")
        for p in self.pins:
            on_box = any((x <= p[0] <= x + w and p[1] in (y, y + h)) or (y <= p[1] <= y + h and p[0] in (x, x + w))
                         for x, y, w, h, _ in self.boxes)
            if not on_box and p not in allow_free_ends:
                self.errors.append(f"arrow at {p} ends in empty space")

    def save(self, path, free_ends=()):
        """Check the rules, then write <figure>.svg beside the figure script."""
        self._check(set(free_ends))
        if self.errors:
            sys.exit(f"{self.name}: diagram rule violations:\n  " + "\n  ".join(self.errors))
        out = os.path.splitext(os.path.abspath(path))[0] + ".svg"
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" '
                f'height="{self.h}" font-family="{FONT}" fill="#000">\n<title>{escape(self.name)}</title>\n'
                '<defs><marker id="arrow" viewBox="0 0 8 8" refX="7.5" refY="4" markerWidth="8" markerHeight="8" '
                'markerUnits="userSpaceOnUse" orient="auto"><path d="M0,0.8 L7.5,4 L0,7.2 z" fill="#000"/></marker></defs>\n'
                f'<rect width="{self.w}" height="{self.h}" fill="#fff"/>\n')
        with open(out, "w", encoding="utf-8") as f:
            f.write(head + "\n".join(self.items) + "\n</svg>\n")
        print(f"wrote {out}")
