# `smx_core` — Block design document

| Trường | Giá trị |
|---|---|
| Trạng thái | DRAFT — Chau ủy quyền viết RTL trước khi duyệt (2026-11-03), chưa duyệt |
| File RTL | `rtl/core/smx_core.sv` |
| Testbench | `tb/tb_smx_core.sv` (vector: `model/vec_core.py`) |
| Yêu cầu liên quan | REQ-IF-06, REQ-IF-10, REQ-FUN-03, REQ-FUN-04, REQ-FUN-05, REQ-PRF-03, REQ-VER-01, REQ-VER-02, REQ-VER-04 |
| Golden model | `softmax_row(q, K, P, n_seg)` trong `model/softmax_ref.py`, so cả hàng bit-exact. `smx_core` không có công thức riêng |

## 1. Chức năng

`smx_core` là top của lõi: nối CSR, X_BUF, Y_BUF, `smx_ctrl` và datapath (`smx_scale`, `smx_maxtree`, `smx_exp2`, `smx_sumacc`, `smx_divider`, `smx_norm`, mỗi block lane có `P` bản), cộng phần sideband duy nhất mà hợp đồng giao cho nó: một shift register mang thẻ nhóm từ `smx_ctrl` tới đúng tầng pipeline cần (`cross-block.md` mục 1.2 và 3). Không có phép tính số học trong block này; mọi số học nằm ở block con. Ngoài ra nó có hai mux địa chỉ/ghi (mục 4) và hai đường trễ dữ liệu `smx_delay` (u và dm).

Nó không chứa Avalon: cổng ngoài là `acc_*` (REQ-IF-06) cùng conduit `status_*` (REQ-IF-10); `smx_avalon` là việc của nhóm implement.

## 2. Tham số

| Tham số | Mặc định | Nguồn | Ràng buộc |
|---|---|---|---|
| `P` | 8 | `smx_pkg::P` | ∈ {4, 8, 16}; truyền xuống mọi block con có `P` |
| `N_SEG` | 8 | `smx_pkg::N_SEG` | ∈ {4, 8, 16}; truyền cho `smx_exp2` và `smx_csr` (HW_PARAM) |

Nội bộ (không ghi đè): `BANKS = P/4`, `ADDR_W = $clog2(8192/P)`, `TW = 3 + P` (độ rộng thẻ dữ liệu), các điểm rút `T_*` tính từ hằng số latency của `smx_pkg` (mục 4.2).

## 3. Giao diện

| Port | Hướng | Độ rộng | Mô tả |
|---|---|---|---|
| `clk` | in | 1 | |
| `rst_n` | in | 1 | active-low, assert bất đồng bộ; lõi không có bộ đồng bộ, bên lái phải deassert đồng bộ (trong mô phỏng là testbench, `open-decisions.md` A2) |
| `acc_addr` | in | 13 | word address (mục 4.1 của `cross-block.md`) |
| `acc_write` | in | 1 | |
| `acc_writedata` | in | 32 | |
| `acc_byteenable` | in | 4 | |
| `acc_read` | in | 1 | |
| `acc_readdata` | out | 32 | đúng `ACC_RD_LAT = 2` chu kỳ sau `acc_read`, không stall |
| `status_busy`, `status_done`, `status_err` | out | 1 | bit STATUS, đồng bộ |

Pipeline cố định, không stall, không backpressure. Chỉ thanh ghi điều khiển (valid, FSM, CSR) có reset; thẻ dữ liệu và datapath không (quy tắc 4, mục 1 của hợp đồng).

## 4. Hành vi và số học

`smx_core` không có số học. Đối chiếu golden model do testbench làm: `softmax_row(q, K, P=P, n_seg=N_SEG)` cho từng hàng, so mọi `Y[r][i]` với `i < L` bằng `!==`, và `CYCLE_CNT = R·(2·G + ROW_OVERHEAD) + 1`.

### 4.1. Nối dây

| Việc | Cách nối | Cơ sở |
|---|---|---|
| X_BUF `rd_addr` | `status_busy ? grp_addr : buf_rd_addr` | cross-block 4.10; đọc X_BUF từ `acc_*` khi BUSY là không xác định (REQ-IF-09) |
| Y_BUF `rd_addr` | `buf_rd_addr` | |
| Y_BUF ghi | `wr_en = {BANKS{y_valid}}`, `wr_be = 4'hF`, `wr_addr = y_wr_addr`, `wr_data` = `y_out` của lane `j` ở `[8j +: 8]`, lane 0 thấp | `y_wr_addr` tổ hợp từ `smx_ctrl` nên đúng chu kỳ `y_valid` |
| X_BUF ghi | trực tiếp từ cổng `x_wr_*` của `smx_csr` | |
| `smx_scale` lane `j` | `q_in = x_rd_data[8j +: 8]`, `k_in = k` (CSR) | lane 0 = byte thấp, REQ-IF-07 |
| `smx_exp2` lane `j` | `u_in` = `u_out` đã trễ `MAXTREE_LAT`, `m_in = m_out` của `smx_maxtree` (cùng dây ở cả hai lượt), `in_en = en[j]` tại điểm EXP | ở lượt 2 `smx_maxtree` không nhận `in_valid` nên `m_out` giữ M cuối hàng |
| `smx_maxtree` | `in_valid = valid & ~pass2` tại điểm MAXT, `in_first = first`, `in_en = en`, `c_in` = `c_out` các lane | |
| `smx_sumacc` | `in_valid = valid & ~pass2` tại điểm E, `in_first = first`, `e_in` = `e_out` các lane, `dm_in` = `dm_out` trễ `EXP2_LAT` | |
| `smx_norm` lane `j` | `in_valid = valid & pass2` tại điểm E, `e_in = e_out[j]`, `rcp_in = rcp_out` | |
| `smx_divider` | `start = div_start` (ctrl), `sum_in = sum_out`, `done → div_done`, `rcp_out → mọi lane norm` | |
| `out_valid` của block con | để trống; sự kiện dùng sideband | cross-block mục 4 |

### 4.2. Sideband

Thẻ nhóm `{valid, pass2, first, last, en[P]}` từ `smx_ctrl` đi qua shift register sâu `D_MAX` ô. Ô thứ `d` là thẻ của nhóm phát ra `d` chu kỳ trước. Bit `valid` có reset không đồng bộ; các bit còn lại nằm trong khối `always_ff` không reset, vì chúng chỉ có nghĩa kèm `valid = 1`. Các điểm rút đều tính từ hằng số `smx_pkg`, không dùng số cứng:

| Điểm | Số chu kỳ | Dùng cho |
|---|---|---|
| `T_SCALE` | `BUF_LAT` | `valid` → `smx_scale.in_valid` |
| `T_MAXT` | `T_SCALE + SCALE_LAT` | `valid & ~pass2`, `first`, `en` → `smx_maxtree` |
| `T_EXP` | `T_MAXT + MAXTREE_LAT` | `valid`, `en[j]` → `smx_exp2` |
| `T_E` | `T_EXP + EXP2_LAT` | lượt 1 `valid & ~pass2`, `first` → `smx_sumacc`; lượt 2 `valid & pass2` → `smx_norm` |
| `T_SUM` | `T_E + SUMACC_LAT` | `sum_last = valid & ~pass2 & last` → `smx_ctrl` |
| `T_Y` | `T_E + NORM_LAT` | `y_valid = valid & pass2`, `y_last = y_valid & last` → `smx_ctrl` và `wr_en` của Y_BUF |

Với `smx_pkg` hiện tại: 1, 4, 6, 9, 12, 12. Đổi một latency chỉ cần sửa `smx_pkg`.

Hai đường trễ dữ liệu dùng `smx_delay` (cùng tiện ích, không reset): `u` (`P·U_W` bit, `MAXTREE_LAT` chu kỳ) để `u` tới `smx_exp2` cùng chu kỳ với `m_out` của nhóm mình; `dm` (`DM_W` bit, `EXP2_LAT` chu kỳ) để `dm` tới `smx_sumacc` cùng `E`. **`smx_delay` không có testbench riêng**: bench này thực thi nó, và lỗi chênh một chu kỳ ở một trong hai tap làm sai Y ngay ở hàng có M tăng (đã chứng minh ở mục 8).

## 5. Cấu trúc bên trong

![smx_core](../fig/smx_core.svg)

Thanh ghi: shift register `D_MAX = 12` ô × (1 valid có reset + `3 + P` bit dữ liệu), cộng hai `smx_delay` (`P·25·2` bit và `8·3` bit). Bộ nhân, RAM: nằm trong block con.

## 6. Timing

Dạng sóng: `docs/spec/wave/smx_core.json`, một hàng `L` ngắn, thu nhỏ latency để thấy các pha. Số chu kỳ thật:

- `T_row = 2·G + ROW_OVERHEAD` (`ROW_OVERHEAD = 54`), `CYCLE_CNT = R·T_row + 1`: testbench đếm số chu kỳ `BUSY = 1` ở chân conduit và đọc `CYCLE_CNT`, so cả hai với công thức dùng `smx_pkg::ROW_OVERHEAD`.
- BUSY lên ngay chu kỳ sau START, DONE chỉ lên khi BUSY đã xuống, không bao giờ cùng 1.

Đường găng đo bằng `quartus_sta` trên kết quả Fitter, góc xấu nhất (slow 1100 mV, 0 °C), seed 1:

| P | Slack setup | Đường găng nhất |
|---|---|---|
| 4 | 3,280 ns | `smx_exp2.s2_prod_q` → `e_q`, rồi `s2_dm_q` → `sum_q` (3,312 ns) |
| 8 | 1,809 ns | M10K của `tag_q` (bit `en`) → `smx_maxtree.s1_a_q`; `s3_c_q` → `s1_a_q` là 2,037 ns |
| 16 | 0,789 ns | `tag_q`, `s3_c_q` → `smx_maxtree.s1_a_q` (0,790 ns) |

Vòng tích luỹ `sum_q`, điểm găng dự đoán trong `architecture.md` mục 4, không phải đường găng nhất ở P = 8, 16. Ở P = 8, Quartus chuyển các chuỗi không reset thành `altshift_taps` trong M10K: `tag_q` bit `en` (`tag_q_rtl_0`, 8 bit × 4) và `tag_q` bit `pass2` gộp với `u_u_dly` và `s3_u_q` của `smx_scale` (`tag_q_rtl_1`, 193 bit × 3). Ngõ ra RAM chậm nên đường `en` → tầng 1 cây max thành găng nhất. Quyết định xử lý: `open-decisions.md` A5.

Hold dương ở cả bốn góc (nhỏ nhất 0,027 ns, P = 8, slow 0 °C). Các số trên chỉ gồm đường thanh ghi tới thanh ghi, vì SDC chỉ có clock; `acc_*` và `rst_n` không được ràng buộc nên Fitter không tối ưu chúng (`open-decisions.md` A7).

## 7. Tài nguyên ước tính

Số thật từ `quartus_map` (Analysis & Synthesis, 0 error, 0 warning), `DEPS="smx_delay smx_exp2 smx_scale smx_maxtree smx_sumacc smx_divider smx_norm smx_buf smx_csr smx_ctrl" syn/map_check.sh smx_core P=4,8,16`:

| P | Combinational ALUT | Registers | Block memory bits | DSP |
|---|---|---|---|---|
| 4 | 984 | 1494 | 131 072 | 12 |
| 8 | 1664 | 2477 | 131 072 | 24 |
| 16 | 2987 | 4474 | 131 072 | 48 |

131 072 bit = hai buffer 65 536 bit: không bị chuyển thành flip-flop.

Số thật sau Fitter, `syn/fit.sh P 8 SEED` (Quartus Prime Lite 18.1, 5CSXFC6D6F31C6, 100 MHz). Tài nguyên ở seed 1; Fmax là số nhỏ hơn của hai góc slow 85 °C và 0 °C:

| P | ALM | ALUT logic | Thanh ghi | M10K | Block memory bits | DSP | Fmax, seed 1 / 2 / 3 (MHz) |
|---|---|---|---|---|---|---|---|
| 4 | 645 | 991 | 860 | 18 | 131 363 | 12 | 148,81 / chưa chạy / chưa chạy |
| 8 | 1 035 | 1 681 | 1 211 | 21 | 131 683 | 24 | 122,09 / 129,87 / 134,41 |
| 16 | 1 821 | 2 994 | 2 011 | 33 | 132 227 | 48 | 108,57 / 112,94 / 107,83 |

Thanh ghi ít hơn bảng `map_check` vì luồng đầy đủ chuyển một phần shift register sang M10K (131 683 so với 131 072 bit): ở P = 8, 2 477 thanh ghi của `map_check` còn 1 874 sau Analysis & Synthesis của luồng đầy đủ và 1 211 sau Fitter. M10K gồm X_BUF 8/8/16 khối, phần sideband và trễ `u` 3/6/10 khối (P = 4/8/16), Y_BUF 7 khối. Số 7 của Y_BUF suy từ tổng, vì các dòng Y_BUF trong Fitter RAM Summary cộng lại không khớp tổng; khi tắt suy luận shift register, tổng còn đúng 15 khối ở P = 8 và 23 khối ở P = 16, khớp với số suy ra. Nhiều khả năng Quartus gộp các RAM Y_BUF vì chúng cùng địa chỉ và cùng cho phép ghi [TK].

Chênh lệch giữa các seed tới 10 % ở P = 8, nên so sánh hai phương án phải qua nhiều seed. REQ-PRF-01 (≥ 100 MHz) đạt ở mọi lần chạy, sát nhất là 107,83 MHz (P = 16, seed 3). REQ-RES-01 đạt (1 681 ALUT + 24 DSP ở P = 8).

## 8. Kế hoạch kiểm thử block

`tb/tb_smx_core.sv` chỉ lái `acc_*` như phần mềm, tôn trọng read latency 2 (đọc liên tiếp một lệnh mỗi chu kỳ). Vector từ `model/vec_core.py` (định dạng ở đầu file đó): mỗi run gồm `L`, `R`, `K`, từng hàng đầu vào và Y kỳ vọng từ `softmax_row(q, K, P, n_seg)`. Cái nhìn duy nhất vào trong DUT là một bộ đếm thụ động số lần ghi Y_BUF, vì lần chạy lại y hệt không thể hiện gì qua `acc_*`.

Phủ (REQ-VER-02 đủ): L ∈ {1, P−1, P, P+1, 2P−1, 2P+1, L_MAX} × K ∈ {0, 1, 5909, 65535} với R = 2; R = 1 cho mỗi L; R = R_MAX (L = 1, P+1, 37, 128, 2P+1) và L_MAX với R_MAX ở K = 5909, 0, 65535; mười hai loại hàng (toàn −128, toàn 127, đồng nhất, one-hot hai cực, max chỉ ở nhóm cuối, tăng dần, giảm dần, ngẫu nhiên toàn dải và dải hẹp, max ở nhóm đầu, max ở phần tử cuối), các hàng trong một run khác nhau; 24 run ngẫu nhiên; năm run lặp lại ca cũ (REQ-FUN-05). Bổ sung: mọi L ∈ 1..512, `sum = 2¹⁴`, `dM = 254` ở từng vị trí nhóm, one-hot ở từng vị trí của hàng ngắn, một run có hàng dao động giữa `sum` lớn nhất và nhỏ nhất.

Kiểm:
- Mọi `Y[r][i]`, `i < L`, đọc cả vùng qua `acc_*`, so bit-exact; phần tử `L ≤ i < G·P` không có X.
- REQ-FUN-03: phần tử X_BUF ở `i ≥ L` được ghi rác ngẫu nhiên (gồm 127 và −128), hoặc để chưa ghi (ba run đầu, địa chỉ chưa ghi bao giờ nên là X trong mô phỏng; bench đòi thấy ít nhất một byte X khi đọc lại).
- `CYCLE_CNT` và số chu kỳ BUSY đo độc lập đều bằng `R·(2G + ROW_OVERHEAD) + 1` ở mọi run (REQ-VER-04); BUSY ngay sau START; DONE chỉ ở cuối; monitor mỗi chu kỳ kiểm không bao giờ BUSY & DONE, không X trên chân.
- Chạy liên tiếp: các run không có khoảng cách; run cờ bit 1 START lại ngay chu kỳ DONE xuất hiện, và số lần ghi Y_BUF phải đủ `R·G`.
- Run cờ bit 3 (cặp): không đọc Y của run đầu, ghi K của run sau một chu kỳ sau DONE rồi START; hai run cùng hàng, Y khác nhau ở mọi hàng nên Y cũ không thể lọt.
- Run cờ bit 4: traffic bus ngẫu nhiên mỗi chu kỳ BUSY. Đọc CSR được kiểm ở latency 2, kể cả `CYCLE_CNT` và STATUS; ghi LEN, ROWS, SCALE_K, X_BUF, Y_BUF, STATUS, CYCLE_CNT, CTRL phải không có tác dụng và được đọc lại sau run.
- Reset giữa lần chạy ở chín điểm (2, 12, T/5, T/3, T/2, 3T/5, 4T/5, T−3, T−1 chu kỳ sau START): trạng thái xoá ngay, các thanh ghi về 0, rồi một lần chạy đầy đủ đúng. Run bị huỷ là run cặp có Y khác, nên Y_BUF không chứa sẵn kết quả đúng.
- ERR: LEN = 0, 513, 1023; ROWS = 0, 17, 31; cả hai 0: DONE = ERR = 1, BUSY không lên, STATUS = 6, CYCLE_CNT = 0, rồi một run tốt chạy đúng.
- Ghi/đọc X_BUF với byte enable (literal cố định, ghi be = 0 không đổi gì), `HW_PARAM`, vùng không định nghĩa đọc 0, đọc luân phiên hai nguồn đúng latency 2.

Cố ý làm sai tích hợp (mỗi lần một lỗi, `make` báo lỗi rồi khôi phục): trễ dm thêm một chu kỳ (`EXP2_LAT + 1`): sai Y ở nhiều run có M tăng, ví dụ `Y[0][8] = 80, want ff` ở L = 9, K = 65535; đổi `first` thành `last` ở `smx_sumacc`: `Y[0][i] = ff, want 1c` ở run đầu; đảo cực mux X_BUF: sai X_BUF đọc lại; dời tap Y một chu kỳ: `busy cycles 60, want 59` và `CYCLE_CNT` sai.

Kết quả 2026-11-04: `make regress testname=tb_smx_core PS="4 8 16" N_SEGS="4 8 16" REGEN=1` PASS cả 9 tổ hợp (ModelSim ASE 10.5b). Ở P = 8, N_SEG = 8: 783 run, 354 324 byte Y, 16 129 lần đọc được kiểm trong BUSY.

Rà soát độc lập 2026-11-03 (bench riêng, không nằm trong repo; báo cáo tổng kết bị mất do hết quota, số dưới đây lấy từ log của nó): 7 tổ hợp P, N_SEG với 27 305 hàng và 4 023 054 phần tử, cộng quét đủ 65 536 giá trị K ở P = N_SEG = 8, đều PASS. Rà soát này cho thấy bench cũ bỏ sót ba mutation, nên mới có các phần bổ sung ở trên. Bench hiện tại bắt 11/11 mutation tại P = N_SEG = 8: đọc bus cướp địa chỉ X_BUF khi BUSY; mất ghi Y sau reset, sau restart cách DONE 0 hoặc 1 chu kỳ (hai mutation); ghi X_BUF, LEN, ROWS, SCALE_K khi BUSY (bốn mutation); START khi BUSY xoá `CYCLE_CNT`; bỏ `first` ở `smx_sumacc` và ở `smx_maxtree` (hai mutation). Hai mutation `first` bị bắt nhờ X ngay ở run đầu; trên phần cứng tương đương là tổng cũ cộng dồn, không có X để lộ.

## 9. Câu hỏi mở / quyết định cần duyệt

- [ ] Q1. Sideband dùng một shift register chung sâu 12 ô, mỗi tap đọc đúng ô cần, thay vì nhiều đường trễ nhỏ. Khuyến nghị giữ: một chỗ sửa khi đổi latency. Quartus đưa một phần chuỗi này vào M10K và đó là đường găng nhất ở P = 8 (mục 6), nhưng tắt suy luận không cho lợi Fmax rõ ràng qua 3 seed (`open-decisions.md` A5).
- [ ] Q2. `status_busy` chọn địa chỉ X_BUF là một mux nhỏ trên đường tới RAM. Fitter không xếp đường này vào nhóm găng nhất ở mục 6, nên khuyến nghị giữ nguyên.

## 10. Lịch sử

- 2026-11-03: tạo DRAFT cùng RTL và testbench (Chau ủy quyền viết RTL trước khi duyệt).
- 2026-11-04: thêm số Fitter và đường găng thật; siết testbench sau rà soát độc lập.
