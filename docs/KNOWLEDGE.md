# KNOWLEDGE — smx (bản tóm tắt để đọc đầu phiên)

> Bản nén của `PROJECT.md` và `requirements.md`. Đọc file này trước; chỉ mở tài liệu gốc khi cần chi tiết hoặc khi sửa số học/giao diện. Nguồn chân lý số học: `model/softmax_ref.py`.

## 1. Đề tài và phạm vi

- BTL môn Cấu trúc phần cứng cho giải thuật học máy, nhóm 6. Hạn ≈ **2026-12-21**.
- IP Avalon-MM slave 32 bit trên DE10-Standard (Cyclone V 5CSXFC6D6F31C6), Quartus Prime Lite 18.1.
- Tính softmax theo hàng cho điểm attention INT8 → UINT8 (scale 1/256).
- **Target workload (D18): DeiT-Tiny** — softmax trong MHSA, L = 197, 3 head × 12 layer, một hàng = một query của một head, một lần chạy = một head (một K). Chỉ softmax là integer, phần còn lại FP32 trên host. Độ chính xác toàn mạng đo bằng golden model; board chạy một layer hardware-in-the-loop. Chi tiết: `docs/spec/target-workload.md`.
- **Chau** làm lõi `smx_core` (CSR, X_BUF, Y_BUF, controller, datapath). **Ưu tiên lõi trước.** Wrapper `smx_avalon`, `ip/smx_hw.tcl`, Platform Designer và script System Console thuộc nhóm implement — không tự viết.
- Verification do nhóm khác làm, dùng golden model làm scoreboard.
- Không đưa GEMM, convolution hay "activation accelerator" vào trọng tâm (trùng nhóm 1, 2, 5, 7, 8, 9).

## 2. Thuật toán (bit-exact với `model/softmax_ref.py`)

- `K = round(S·log₂e·2¹⁶)` do HPS tính, ghi vào `SCALE_K` (UQ0.16). Phần cứng không có hàm log.
- `u = q·K` (25 bit, Q8.16); `c = ⌈u / 2¹⁶⌉` (9 bit có dấu).
- `E(d)` với `d ≤ 0`: `I = d >> 16`, `F = d & 0xFFFF`, `idx = F >> 13`, `r = F & 0x1FFF` (N_SEG = 8); `E₀ = C[idx] + ((M_[idx]·r) >> 13)`; `E = 0` nếu `−I > 15`, ngược lại `E = E₀ >> (−I)`.
- **Lượt 1** (online normalization, IntMax): theo nhóm P = 8 phần tử tăng dần; `Mnew = max(M, Mg)`; `sum = (sum >> (Mnew−M)) + Σ E(u_k − Mnew·2¹⁶)`.
- `Rcp = ⌊2⁴⁰ / sum⌋` (27 bit).
- **Lượt 2** (tính lại E từ X_BUF, không lưu trung gian): `y = min(255, (E·Rcp + 2³¹) >> 32)`.
- Sai số đo được ≈ 0,00195–0,0020 so với float64 (bằng nửa LSB UINT8).

## 3. Tham số

| Tham số | Giá trị |
|---|---|
| P (lane) | 8 (kiểm 4/8/16) |
| L_MAX | 512 |
| R_MAX | 16 |
| N_SEG | 8 |
| K_FRAC | 16 |

Latency mục tiêu: ≤ `2·⌈L/P⌉ + 64` chu kỳ/hàng (L = 512 → ≤ 192). Fmax mục tiêu ≥ 100 MHz. Tài nguyên: > 1000 ALUT + DSP.

Số đo (`syn/fit.sh`, góc slow xấu hơn, 3 seed; chi tiết `docs/spec/blocks/smx_core.md` mục 6, 7): P = 8 đạt 122–134 MHz với 1 681 ALUT, 24 DSP, 21 M10K; P = 16 đạt 108–113 MHz; P = 4 đạt 149 MHz (1 seed). Chỉ tính đường thanh ghi tới thanh ghi. `T_row = 2G + 54` chu kỳ.

## 4. Giao diện

- Avalon-MM slave, 32 bit, word address, không burst, không waitrequest, **readLatency = 2**, có byteenable 4 bit.
- Polling `DONE`, không IRQ. Conduit trạng thái: `status_busy`, `status_done`, `status_err`.
- Ranh giới lõi: `acc_addr` (word 13 bit), `acc_write`, `acc_writedata`, `acc_byteenable`, `acc_read`, `acc_readdata`, read latency 2, không stall. Verify lõi qua cổng này.

Bản đồ thanh ghi (offset byte, span 0x6000):

| Offset | Tên | Ghi chú |
|---|---|---|
| 0x0000 | CTRL | W: bit0 START (tự xoá) |
| 0x0004 | STATUS | R: BUSY[0], DONE[1], ERR[2] |
| 0x0008 | LEN | R/W, [9:0], 1..512 |
| 0x000C | ROWS | R/W, [4:0], 1..16 |
| 0x0010 | SCALE_K | R/W, [15:0] |
| 0x0014 | CYCLE_CNT | R, chu kỳ START→DONE |
| 0x0018 | HW_PARAM | R, VERSION [31:24] = 0x10 |
| 0x2000–0x3FFF | X_BUF | INT8, hàng r phần tử i tại byte `r·512 + i` |
| 0x4000–0x5FFF | Y_BUF | UINT8, cùng bố trí |

Đóng gói little-endian, 4 phần tử/word. Thanh ghi chưa định nghĩa đọc 0. Đọc X/Y_BUF khi BUSY = 1 là không xác định.

## 5. Quy tắc cứng

1. RTL phải khớp golden bit-exact. Đổi số học → đổi model trước, ghi nhật ký, rồi mới sửa RTL.
2. Requirements v1.0 đã đóng băng. Đổi giao diện phải hỏi người dùng, tăng VERSION, ghi nhật ký.
3. Không bịa số tổng hợp, Fmax, latency. Số ước lượng ghi [TK], số đo ghi nguồn.
4. Không viết RTL cho block chưa `APPROVED` (theo `docs/spec/blocks/README.md`).
5. SystemVerilog tập con Quartus 18.1: không `initial` (trừ `$readmemh`), không `$display`, không SVA trong file tổng hợp, một module một file, tên module tiền tố `smx_`.

## 6. Thứ tự block và trạng thái

`smx_exp2` → `smx_scale` → `smx_maxtree` → `smx_sumacc` → `smx_divider` → `smx_norm` → `smx_buf` → `smx_csr` → `smx_ctrl` → `smx_core`. Trạng thái hiện tại xem `docs/spec/blocks/README.md`.

## 7. Lệnh hay dùng

```bash
python3 model/softmax_ref.py --selftest
python3 model/softmax_ref.py --gen-pwl 8
python3 model/softmax_ref.py --gen-hex 8 rtl/pkg/pwl_n8.hex
syn/map_check.sh smx_exp2 N_SEG=4,8,16     # quartus_map, không phải số Fitter/Fmax
syn/fit.sh 8 8 1                           # P N_SEG SEED: Fitter đầy đủ cho smx_core, in tài nguyên và Fmax
```

Môi trường Python: `source ~/venvs/ml/bin/activate` (xem `setup` ở thư mục gốc).

**Mô phỏng** dùng một flow duy nhất ở `sim/`, cùng cách tổ chức với repo `risc_v` của Chau (`milestone3/10_sim`). Chạy từ `sim/`:

```bash
make                                 # clean + build + run (mặc định tb_smx_exp2, P=8, N_SEG=8)
make testname=tb_smx_exp2 N_SEG=16   # testname là tên module top
make regress                         # build một lần, chạy mọi tổ hợp PS × N_SEGS
make regress PS="4 8 16" N_SEGS=8    # quét P thay vì N_SEG
make run WAVE=1                      # chạy lại không compile, ghi wave/<run>.wlf
make dump | view | clean
```

- `compile.f` = `rtl.f` + `tb.f` + `testcase.f`. Block mới: thêm RTL vào `rtl.f` (sau `smx_pkg.sv`, khối con trước khối cha) và `tb_<block>.sv` vào `testcase.f`. Không viết script chạy riêng trong `tb/`.
- Test đạt khi log có `TB_RESULT: PASS`, nên mọi testbench phải in đúng dòng này. Log ở `sim/log/<testname>_p<P>_n<N_SEG>.log`, `sim/sim.log` trỏ tới lần chạy gần nhất.
- Vector tự sinh vào `tb/vectors/smx_<block>/p<P>_n<N_SEG>/` bằng `model/gen_vectors.py <block>` (block mới: thêm `model/vec_<block>.py`, tự được nhận); `REGEN=1` để sinh lại. Sau khi đổi model hoặc `gen_vectors.py` phải chạy với `REGEN=1`, vì vector cũ không tự cập nhật.
- Mọi testbench khai báo tham số `P`, `N_SEG` và nhận plusarg `+VECDIR`; mọi lệnh con của `gen_vectors.py` nhận `--p`, `--n-seg`, `--seed`, `--out`. Block mới khác các điều này thì sửa `Makefile`, không tách flow.
- `make` và `make clean` xoá `wave/`, `log/`, `work/`. Muốn giữ wave thì dùng `make run WAVE=1`. Mỗi file wave của `smx_exp2` khoảng 70 MB.

## 8. Câu hỏi còn mở (từ PROJECT.md mục 9)

- Đã điền tên đề tài vào sheet nhóm 6 chưa?
- Ngày nộp chính xác; có báo cáo giữa kỳ không?
- Nhóm verify dùng ModelSim Starter hay Questa?
- Nhóm implement có dùng JTAG to Avalon Master Bridge trong hệ thống không?
- Workload DeiT-Tiny: tập dữ liệu đánh giá, cách hiệu chuẩn S, layer chạy trên board (`target-workload.md` mục 8).

## 9. Đọc tài liệu gốc khi nào

- `docs/PROJECT.md`: quyết định D1–D17, bảng nguồn từng số liệu (mục 7.1), nhật ký (mục 10).
- `docs/requirements.md`: REQ-* đầy đủ, bản đồ thanh ghi chi tiết, kịch bản verify (REQ-VER-02).
- `docs/spec/design-spec.md`: bản gộp, đọc một file để hiểu thiết kế: hoạt động từng bước, interface, sơ đồ, số đo.
- `docs/spec/architecture.md`: sơ đồ top, FSM, điểm găng timing.
- `docs/spec/integration-notes.md`: bàn giao cho nhóm implement.
- `docs/spec/target-workload.md`: DeiT-Tiny — ánh xạ lên smx, lượng tử hoá điểm, kế hoạch đánh giá E1–E3, phương án đã loại.
- `docs/research/softmax-survey.md`: lý do chọn kiến trúc. `docs/archive/` không dùng làm định hướng.
