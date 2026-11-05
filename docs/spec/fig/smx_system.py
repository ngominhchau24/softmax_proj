"""System around the core: PC, JTAG master, wrapper, core. Run: python3 docs/spec/fig/smx_system.py"""
from schematic import Sheet

s = Sheet("smx_system", 1130, 220)
s.boundary(240, 30, 760, 170, "FPGA system (implement team)")
s.box(20, 70, 140, 60, "PC", "Python, System Console")
s.box(280, 70, 140, 60, "JTAG to Avalon", "Master Bridge")
s.box(540, 70, 130, 60, "smx_avalon", "thin wrapper")
s.box(800, 70, 130, 60, "smx_core")
s.wire([(160, 100), (280, 100)], "USB-Blaster")
s.wire([(420, 100), (540, 100)], "Avalon-MM, 32 bit")
s.wire([(670, 100), (800, 100)], "acc_*, read latency 2")
s.wire([(930, 80), (1110, 80)], "status_busy", lx=1010, port=True)
s.wire([(930, 100), (1110, 100)], "status_done", lx=1010, port=True)
s.wire([(930, 120), (1110, 120)], "status_err", lx=1010, port=True)
s.note(680, 170, "status_* can drive LEDs; leaving them open has no effect.")
s.save(__file__)
