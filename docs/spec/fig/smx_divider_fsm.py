"""smx_divider control. Run: python3 docs/spec/fig/smx_divider_fsm.py"""
from schematic import Sheet

s = Sheet("smx_divider_fsm", 880, 240)
s.box(200, 80, 120, 60, "IDLE", "busy_q = 0")
s.box(560, 80, 120, 60, "BUSY", "busy_q = 1")
s.wire([(120, 110), (200, 110)], "reset")
s.wire([(320, 100), (560, 100)], "start / load, cnt = 0")
s.wire([(560, 120), (320, 120)], "cnt == 26 / load rcp_q, done_q = 1", side="below")
s.wire([(680, 100), (760, 100), (760, 40), (620, 40), (620, 80)], "cnt < 26 / next bit", at=2, lx=630)
s.wire([(680, 120), (760, 120), (760, 180), (620, 180), (620, 140)], "start / reload (undefined use)", at=2, side="below", lx=620)
s.save(__file__)
