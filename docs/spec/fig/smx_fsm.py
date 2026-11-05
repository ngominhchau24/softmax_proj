"""smx_ctrl state machine. Run: python3 docs/spec/fig/smx_fsm.py"""
from schematic import Sheet

s = Sheet("smx_fsm", 1100, 340)
s.box(200, 60, 120, 60, "IDLE")
s.box(440, 60, 120, 60, "P1_RUN", "issue groups")
s.box(680, 60, 120, 60, "P1_DRAIN")
s.box(920, 60, 120, 60, "DIV", "div_start = 1")
s.box(920, 240, 120, 60, "DIV_WAIT")
s.box(680, 240, 120, 60, "P2_RUN", "issue groups")
s.box(440, 240, 120, 60, "P2_DRAIN")
s.box(200, 240, 120, 60, "NEXT_ROW")

s.wire([(130, 90), (200, 90)], "reset")
s.wire([(320, 90), (440, 90)], "start / r = 0")
s.wire([(560, 90), (680, 90)], "last group issued")
s.wire([(800, 90), (920, 90)], "sum_last")
s.wire([(980, 120), (980, 240)], "one cycle")
s.wire([(920, 270), (800, 270)], "div_done")
s.wire([(680, 270), (560, 270)], "last group issued")
s.wire([(440, 270), (320, 270)], "y_last")
s.wire([(230, 240), (230, 120)], "r + 1 == R / run_done = 1", side="left")
s.wire([(280, 240), (280, 180), (500, 180), (500, 120)], "r + 1 < R / r = r + 1", at=1)
s.save(__file__)
