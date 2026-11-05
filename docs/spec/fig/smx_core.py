"""smx_core top-level block diagram. Run: python3 docs/spec/fig/smx_core.py"""
from schematic import Sheet

s = Sheet("smx_core", 1420, 700)
s.boundary(160, 30, 1230, 650, "smx_core")

# ---- blocks ----
s.box(200, 100, 130, 200, "smx_csr", "decode, registers")
s.box(200, 450, 130, 120, "smx_ctrl", "FSM, address, mask")
s.box(460, 100, 100, 80, "X_BUF", "smx_buf")
s.box(460, 220, 100, 40, "BUSY mux")
s.box(660, 100, 120, 60, "smx_scale", "x P")
s.box(660, 310, 120, 50, "smx_delay", "MAXTREE_LAT")
s.box(870, 100, 120, 60, "smx_maxtree")
s.box(870, 310, 120, 50, "smx_exp2", "x P")
s.box(1040, 110, 120, 40, "smx_delay", "EXP2_LAT")
s.box(1040, 310, 120, 50, "smx_sumacc")
s.box(1220, 310, 120, 50, "smx_divider")
s.box(1220, 420, 120, 50, "smx_norm", "x P")
s.box(1220, 510, 120, 70, "Y_BUF", "smx_buf")
s.box(540, 470, 130, 60, "sideband", "shift register")

# ---- port pins: bus slave, so inputs and outputs share the left edge ----
for name, y in [("acc_addr[12:0]", 110), ("acc_write", 130), ("acc_writedata[31:0]", 150),
                ("acc_byteenable[3:0]", 170), ("acc_read", 190)]:
    s.wire([(20, y), (200, y)], name)
for name, y in [("acc_readdata[31:0]", 220), ("status_busy", 240), ("status_done", 260), ("status_err", 280)]:
    s.wire([(200, y), (20, y)], name)

# ---- csr and ctrl ----
s.wire([(220, 450), (220, 300)], "run_done", side="left")
s.wire([(250, 300), (250, 450)], "len, rows, start")

# ---- buffers and read address ----
s.wire([(330, 120), (460, 120)], "x_wr_*")
s.wire([(460, 160), (330, 160)], "x_rd_data, BANKS x 32", bus=True)
s.wire([(330, 240), (460, 240)], "buf_rd_addr", lx=370)
s.wire([(510, 220), (510, 180)], "x_rd_addr")
s.wire([(330, 470), (510, 470), (510, 260)], "grp_addr", lx=390)
s.dot(350, 240)
s.wire([(350, 240), (350, 600), (1250, 600), (1250, 580)], "buf_rd_addr", at=1, lx=390)
s.wire([(1220, 570), (370, 570), (370, 280), (330, 280)], "y_rd_data, BANKS x 32", at=0, bus=True, lx=390)
s.wire([(330, 540), (1220, 540)], "y_wr_addr", lx=390)

# ---- scale constant ----
s.wire([(270, 100), (270, 60), (720, 60), (720, 100)], "k", at=1)

# ---- datapath ----
s.wire([(560, 130), (660, 130)], "q_lane, P x 8", bus=True)
s.wire([(780, 130), (870, 130)], "c_lane, P x 9", bus=True)
s.wire([(720, 160), (720, 310)], "u_lane, P x 25", bus=True)
s.wire([(780, 340), (870, 340)], "u_dly, P x 25", bus=True)
s.wire([(930, 160), (930, 310)], "m_out")
s.wire([(990, 130), (1040, 130)], "dm_out")
s.wire([(1100, 150), (1100, 310)], "dm_dly")
s.wire([(990, 330), (1040, 330)], bus=True)
s.wire([(1160, 330), (1220, 330)], "sum_out")
s.wire([(1280, 360), (1280, 420)], "rcp_out")
s.dot(1020, 330)
s.wire([(1020, 330), (1020, 450), (1220, 450)], "e_lane, P x 16", at=1, bus=True)
s.wire([(1280, 470), (1280, 510)], "y_lane, P x 8", bus=True)

# ---- sideband and events ----
s.wire([(330, 490), (540, 490)], "group tag", lx=390)
s.wire([(540, 510), (330, 510)], "sum_last, y_valid, y_last", lx=390)
s.wire([(670, 500), (830, 500)], "valid, pass2, first, en")
s.note(838, 504, "to scale, maxtree, exp2, sumacc, norm; y_valid to Y_BUF write enable")

# ---- divider handshake ----
s.wire([(270, 570), (270, 640), (1370, 640), (1370, 330), (1340, 330)], "div_start", at=1, lx=390)
s.wire([(1340, 350), (1360, 350), (1360, 620), (310, 620), (310, 570)], "div_done", at=2, lx=390)

s.note(800, 668, "clk and rst_n reach every block and are not drawn. Shown for any P; BANKS = P/4.")
s.save(__file__, free_ends=[(20, y) for y in (220, 240, 260, 280)] + [(830, 500)])
