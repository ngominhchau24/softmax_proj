"""smx_core top-level block diagram. Run: python3 docs/spec/fig/smx_core.py"""
from schematic import Sheet

s = Sheet("smx_core", 1530, 700)
s.boundary(150, 30, 1330, 650, "smx_core")

# ---- blocks ----
s.box(200, 100, 130, 200, "smx_csr", "decode, registers")
s.box(200, 450, 130, 120, "smx_ctrl", "FSM, address, mask")
s.box(460, 100, 100, 80, "X_BUF", "smx_buf")
s.box(460, 220, 100, 40, "BUSY mux")
s.box(660, 100, 120, 60, "smx_scale", "x P")
s.box(660, 310, 120, 50, "smx_delay", "MAXTREE_LAT")
s.box(890, 100, 120, 60, "smx_maxtree")
s.box(890, 310, 120, 50, "smx_exp2", "x P")
s.box(1090, 110, 120, 40, "smx_delay", "EXP2_LAT")
s.box(1090, 310, 120, 50, "smx_sumacc")
s.box(1300, 310, 120, 50, "smx_divider")
s.box(1300, 420, 120, 50, "smx_norm", "x P")
s.box(1300, 510, 120, 70, "Y_BUF", "smx_buf")
s.box(590, 470, 130, 60, "sideband", "shift register")

# ---- port pins: bus slave, so inputs and outputs share the left edge ----
for name, y in [("acc_addr[12:0]", 110), ("acc_write", 130), ("acc_writedata[31:0]", 150),
                ("acc_byteenable[3:0]", 170), ("acc_read", 190)]:
    s.wire([(20, y), (200, y)], name)
for name, y in [("acc_readdata[31:0]", 220), ("status_busy", 240), ("status_done", 260), ("status_err", 280)]:
    s.wire([(200, y), (20, y)], name)

# ---- csr and ctrl ----
s.wire([(210, 450), (210, 300)], "run_done", side="left")
s.wire([(230, 300), (230, 450)], "len[9:0], rows[4:0], start")

# ---- buffers and read address ----
s.wire([(330, 120), (460, 120)], "x_wr_*")
s.wire([(460, 160), (330, 160)], "x_rd_data[63:0]", bus=True)
s.wire([(330, 240), (460, 240)], "buf_rd_addr[9:0]", lx=370)
s.wire([(510, 220), (510, 180)], "x_rd_addr[9:0]")
s.wire([(330, 470), (510, 470), (510, 260)], "grp_addr[9:0]", lx=430)
s.dot(390, 240)
s.wire([(390, 240), (390, 600), (1330, 600), (1330, 580)], "buf_rd_addr[9:0]", at=1, lx=430)
s.wire([(1300, 570), (410, 570), (410, 280), (330, 280)], "y_rd_data[63:0]", at=0, bus=True, lx=430)
s.wire([(330, 540), (1300, 540)], "y_wr_addr[9:0]", lx=430)

# ---- scale constant ----
s.wire([(270, 100), (270, 60), (720, 60), (720, 100)], "k[15:0]", at=1)

# ---- datapath ----
s.wire([(560, 130), (660, 130)], "q_lane[7:0][7:0]", bus=True)
s.wire([(780, 130), (890, 130)], "c_lane[7:0][8:0]", bus=True)
s.wire([(720, 160), (720, 310)], "u_lane[7:0][24:0]", bus=True)
s.wire([(780, 340), (890, 340)], "u_dly[7:0][24:0]", bus=True)
s.wire([(950, 160), (950, 310)], "m_out[8:0]")
s.wire([(1010, 130), (1090, 130)], "dm_out[7:0]")
s.wire([(1150, 150), (1150, 310)], "dm_dly[7:0]")
s.wire([(1010, 330), (1090, 330)], bus=True)
s.wire([(1210, 330), (1300, 330)], "sum_out[24:0]")
s.wire([(1360, 360), (1360, 420)], "rcp_out[26:0]")
s.dot(1050, 330)
s.wire([(1050, 330), (1050, 450), (1300, 450)], "e_lane[7:0][15:0]", at=1, bus=True)
s.wire([(1360, 470), (1360, 510)], "y_lane[7:0][7:0]", bus=True, side="left")

# ---- sideband and events ----
s.wire([(330, 490), (590, 490)], "group tag", lx=430)
s.wire([(590, 510), (330, 510)], "sum_last, y_valid, y_last", lx=430)
s.wire([(720, 500), (880, 500)], "valid, pass2, first, en")
s.note(888, 504, "to scale, maxtree, exp2, sumacc, norm; y_valid to Y_BUF write enable")

# ---- divider handshake ----
s.wire([(270, 570), (270, 640), (1450, 640), (1450, 330), (1420, 330)], "div_start", at=1, lx=430)
s.wire([(1420, 350), (1440, 350), (1440, 620), (310, 620), (310, 570)], "div_done", at=2, lx=430)

s.note(800, 668, "Drawn at P = 8, N_SEG = 8. clk and rst_n reach every block and are not drawn.")
s.save(__file__, free_ends=[(20, y) for y in (220, 240, 260, 280)] + [(880, 500)])
