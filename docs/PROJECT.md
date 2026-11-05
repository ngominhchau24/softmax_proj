# PROJECT.md — BTL: Integer-Only Softmax Accelerator cho Transformer Attention

> Tài liệu nền của project. Mọi phiên làm việc (claude.ai Project hoặc Claude Code CLI) đọc file này trước. Khi có thay đổi: cập nhật **Quyết định** (mục 7) và **Nhật ký** (mục 10). Ký hiệu: `[CHƯA CHỐT]` = còn mở. Mọi quyết định đã chốt đổi được nhưng phải ghi Nhật ký.

---

## 1. Bối cảnh

- **Môn học:** Cấu trúc phần cứng cho giải thuật học máy — Bài tập lớn (BTL), nhóm 6.
- **Đề tài đăng ký:** *Design and FPGA Implementation of an Integer-Only Softmax Accelerator for Transformer Attention*.
- **Phân công:** làm nhóm, nhưng project này coi như bài một người:
  - **Chau:** kiến trúc, micro-architecture, RTL của **`smx_core`** (gồm CSR, X_BUF, Y_BUF, controller, datapath), spec bàn giao, golden model số học. **Ưu tiên: lõi trước.**
  - **Thành viên khác:** verification (testbench, coverage, dùng golden model làm scoreboard) và implement lên kit: wrapper Avalon mỏng `smx_avalon`, `smx_hw.tcl`, hệ thống Platform Designer, script demo System Console (xem `docs/spec/integration-notes.md`).
  - Hệ quả: đầu ra quan trọng nhất là **spec giao diện đóng băng sớm + golden model bit-exact + RTL sạch**.
- **Hạn nộp:** ≈ 2026-12-21 (ngày chính xác `[CHƯA CHỐT]`).
- **Demo:** chứng minh design chạy đúng trên board (nạp vector → chạy → đọc → so golden model, kèm CYCLE_CNT). Workload mục tiêu là DeiT-Tiny (D18): board chạy softmax của một layer theo kiểu hardware-in-the-loop trên vài ảnh; độ chính xác toàn mạng đo bằng golden model trên PC (`docs/spec/target-workload.md`). Không chạy trọn mạng trên FPGA. Đường chính: **JTAG + System Console, hệ thống không HPS, không cần Linux** (D16).

## 2. Yêu cầu của môn

| # | Yêu cầu | Cách đáp ứng |
|---|---|---|
| R1 | Accelerator cho phép toán bên trong mạng AI | Softmax theo hàng trong self-attention của Transformer; target DeiT-Tiny (D18) |
| R2 | > 1000 LUTs sau tổng hợp, tính cả DSP | Đọc Fitter Resource Usage Quartus (ALUT + DSP); kỳ vọng vài nghìn ALUT + 12–24 DSP |
| R3 | Deploy trên kit DE10 | DE10-Standard, tích hợp vào GHRD Terasic |

## 3. Nền tảng

- **Kit:** DE10-Standard — Cyclone V SX 5CSXFC6D6F31C6, ~41,9K ALM, ~5,5 Mbit M10K, 112 DSP, HPS dual Cortex-A9 + 1 GB DDR3 (đối chiếu user manual Terasic khi cần số chính xác).
- **Tích hợp:** IP là Avalon-MM slave 32 bit. Demo: Platform Designer tối giản (Clock Source + JTAG to Avalon Master Bridge + smx), điều khiển từ PC qua USB-Blaster II. Tuỳ chọn: GHRD Terasic qua lightweight HPS-to-FPGA bridge (AXI, Platform Designer tự chuyển sang Avalon). Thuật ngữ: *golden model* = `model/softmax_ref.py`; *GHRD* = thiết kế mẫu Terasic.
- **Toolchain:** Quartus Prime Lite 18.1, Platform Designer 18.1, ModelSim-Intel Starter (hoặc Questa nếu nhóm verify có). Python 3 + NumPy cho golden model.

## 4. Đề tài các nhóm khác — phải tránh trùng

| Nhóm | Đề tài |
|---|---|
| 1 | Adaptive Threshold Activation, Buffer Compression, Zero-skipping |
| 2 | 2D Systolic Array GEMM |
| 5 | INT8 Systolic Array MatMul trong hệ RISC-V |
| 7 | Winograd Convolution cho CNN |
| 8 | Mixed-Precision GEMM |
| 9 | Sparse GEMM, fine-grained dynamic dataflow |
| 3, 4, 10 | TBD / trống (kiểm tra lại sheet) |

Hệ quả: không đưa GEMM, convolution, hay "activation function accelerator" vào trọng tâm. Sigmoid/tanh/GELU chỉ là mở rộng tuỳ chọn và trình bày như "tái sử dụng datapath exp + nghịch đảo" (giáp ranh nhóm 1).

## 5. Kiến trúc tóm tắt

Kiến trúc mức top (sơ đồ mermaid, FSM, điểm găng timing): `docs/spec/architecture.md`. Đặc tả bit-exact: `docs/requirements.md`. Cơ sở lựa chọn: `docs/research/softmax-survey.md`.

```
 Avalon-MM slave ── smx_avalon (CSR decode, X_BUF/Y_BUF port A)
                         │
                    smx_core ── controller FSM (rows, pass1, divide, pass2)
                         │
   X_BUF(M10K, P×8b) ─► [×K DSP] ─► [ceil + IntMax tree] ─► [E(d): shift + PWL 2^F] ─► [Σ tree, renorm >>]
                                                                                           │ sum, M
                                                                                  [seq. divider 2^40/sum]
                                                                                           │ Rcp
   X_BUF (đọc lại)  ─► [×K] ─► [−M] ─► [E(d)] ─► [× Rcp, round, sat] ─► Y_BUF(M10K)
```

Ý tưởng then chốt:
1. **K = S·log₂e** do HPS tính sẵn → phần cứng chỉ nhân q·K để ra số mũ cơ số 2; tính đúng e^x cho mọi scale, không cần fine-tune (khác Softermax), không có sai số cố định của xấp xỉ log₂e bằng dịch (khác Shiftmax). Không có hàm/bảng log nào trong datapath.
2. **IntMax + online normalization** (Softermax/Milakov): max lấy trên ⌈u⌉ nên hiệu chỉnh tổng chỉ là phép dịch → 2 lượt thay vì 3.
3. **2^F bằng PWL N_SEG đoạn** (bảng hằng sinh từ Python, 1 phép nhân) thay cho CORDIC (CORDIC chỉ dùng làm so sánh trong báo cáo).
4. **Một phép chia mỗi hàng** (bộ chia tuần tự), mỗi phần tử chỉ một phép nhân.
5. **Lượt 2 tính lại E** từ X_BUF thay vì lưu kết quả trung gian (bài học SoftGen).

## 6. Quy ước RTL và thư mục

Xem `CLAUDE.md` (quy tắc cho cả người và Claude Code). Tóm tắt: SystemVerilog tập con Quartus 18.1; tên/comment tiếng Anh; lõi tách khỏi wrapper; số học phải khớp `model/softmax_ref.py`.

```
docs/      PROJECT.md, requirements.md, research/, spec/ (micro-arch, interface), archive/
model/     softmax_ref.py (golden, nguồn chân lý số học), sinh bảng PWL, sinh vector
rtl/       pkg/smx_pkg.sv, core/, avalon/
tb/        testbench tự viết cho sanity test (nhóm verify có môi trường riêng)
sim/       Makefile và compile.f (= rtl.f + tb.f + testcase.f) để mô phỏng, chạy từ thư mục này
ip/        smx_hw.tcl (Platform Designer component — nhóm implement)
syn/       project Quartus chỉ cho IP (tài nguyên, Fmax)
sw/        ví dụ mã HPS (driver /dev/mem) — tham khảo cho nhóm implement
```

## 7. Quyết định

**Đã chốt**
- D1 Kit DE10-Standard. D2 GHRD Terasic là phương án tích hợp tuỳ chọn (xem D16). D3 Phạm vi = RTL lõi + spec (chi tiết phân vai ở D17). D4 Demo chỉ cần chạy đúng. D5 Đo tài nguyên = ALUT + DSP (Fitter). D6 Quartus Prime Lite 18.1. D7 Hạn ≈ 2026-12-21. D8 Polling DONE, không IRQ. D9 Lõi tự viết, hạ tầng dùng IP. D11 Không trùng đề tài mục 4.
- D10 ~~GEMM systolic~~ — huỷ (trùng nhóm 2, 5); bản cũ ở `docs/archive/gemm-sa-proposal.md`.
- D12 Đề tài: Integer-Only Softmax Accelerator for Transformer Attention.
- D13 Không có hàm log trong datapath; log₂e gộp vào K tính bởi phần mềm.
- D14 Thứ tự: nhân K trước, IntMax trên ⌈u⌉, rồi E(u − M).
- D15 Bus: Avalon-MM slave 32 bit, có byteenable, readLatency 2, không waitrequest/burst; conduit trạng thái cho LED. Cắm được vào cả hệ thống JTAG master lẫn GHRD.
- D16 Đường demo chính: JTAG + System Console, hệ thống không HPS; GHRD + Linux là mở rộng tuỳ chọn.
- D17 Phân vai: Chau làm `smx_core` (gồm CSR + buffer, cổng `acc_*`), **ưu tiên lõi trước**; wrapper `smx_avalon`, `_hw.tcl`, Platform Designer, script demo thuộc nhóm implement.
- D18 Target workload duy nhất: softmax trong MHSA của **DeiT-Tiny** (`deit_tiny_patch16_224`, ImageNet-1k; L = 197, 3 head × 12 layer). Chỉ softmax là integer, phần còn lại FP32 trên host; scale S theo (layer, head). Đánh giá E1–E3 và phương án đã loại: `docs/spec/target-workload.md`. Không đổi requirements v1.0.

**Chốt v1.0 (Chau duyệt 2026-10-31)** — chi tiết trong `docs/requirements.md` và `docs/spec/architecture.md`
- B1 Đầu vào INT8 có dấu, đầu ra UINT8 scale 1/256.
- B2 P = 8, L_MAX = 512, R_MAX = 16.
- B3 Lượt 2 tính lại E từ X_BUF (không lưu unnormed).
- B4 Nghịch đảo bằng bộ chia tuần tự radix-2 `⌊2⁴⁰/sum⌋`.
- B5 N_SEG = 8.
- B6 Không masking ở v1.0.
- B7 Read latency = 2, không waitrequest; bản đồ thanh ghi requirements mục 5.2.
- A1 Mỗi buffer 2 bank × 32 bit × 1024. A2 Hai lượt online normalization. A3 Không chồng lặp bộ chia ở v1.0. A4 X_BUF/Y_BUF tách riêng. A5 Datapath tham số P (kiểm 4/8/16, nộp 8).

### 7.1. Nguồn của từng quyết định

Ký hiệu loại nguồn: **[TL]** tài liệu đã công bố (số trong ngoặc vuông là mục tham khảo trong `docs/research/softmax-survey.md` mục 7); **[GM]** đo bằng golden model `model/softmax_ref.py --selftest` của project; **[TK]** lựa chọn/ước lượng thiết kế của project, chưa có số liệu đo — phải kiểm lại bằng tổng hợp hoặc mô phỏng; **[ĐC]** kiến thức chung về công cụ/chip, cần đối chiếu tài liệu Intel/Terasic.

| Mục | Nội dung | Nguồn |
|---|---|---|
| B1 | INT8 vào | [TL] I-BERT [2]: MatMul INT8, cộng dồn INT32, phi tuyến xong requantize về INT8; I-ViT [4]: luồng dữ liệu INT8, phi tuyến tính trên INT32 |
| B1 | UINT8 ra, scale cố định | [TL] Shiftmax/I-ViT [4]: đầu ra scale cố định `1/2^(k_out−1)` (ta dùng biến thể không dấu 1/256); Softermax [3]: phương án Q(1,7) |
| B1 | Sai số ≈ 0,00195 (nửa LSB) | [GM] selftest, hàng ngẫu nhiên L = 128, S ∈ {0,02; 0,0625; 0,2} |
| B2 | P = 8 | [TL] SoftGen [6]: song song 16 cho tích diện tích–trễ tốt nhất trong 1–32, 8 và 16 gần như ngang nhau; [TK] khớp bus đọc 64 bit (A1) |
| B2 | L_MAX = 512 | [TL] Softermax [3]: dòng GPT tăng độ dài chuỗi từ 512 lên 2048; workload SQuAD dài 384; [ĐC] BERT-base dùng tối đa 512 token |
| B2 | R_MAX = 16 | [TK] cỡ buffer 8 KB, dư nhiều so với M10K ([ĐC] ~5,5 Mbit trên 5CSXFC6) |
| B3 | Tính lại thay vì lưu | [TL] SoftGen [6]: đọc lại bộ nhớ on-chip giữ diện tích không đổi theo số đầu vào, độ trễ đọc lại che được; SoftGen tính lại phép trừ thay vì lưu FIFO. Phương án lưu + hiệu chỉnh: Softermax [3] |
| B4 | Một phép chia mỗi hàng | [TL] Shiftmax [4]: `⌊2^M/Σ⌋` một lần rồi nhân và dịch; Softermax [3]: PWL reciprocal + nhân nguyên (phương án khác) |
| B4 | Radix-2 tuần tự, 2⁴⁰, ~28 chu kỳ | [TK] chọn độ rộng để `Rcp` ≤ 27 bit; đúng bit kiểm bằng [GM]; số chu kỳ là ước lượng |
| B5 | PWL cho 2^F | [TL] Softermax [3]: PWL 4 đoạn; bài FPGA 2026 [10]: PWL 16 đoạn trong LUTRAM; SoftGen [6]: LUT-PLF 64 đoạn |
| B5 | N_SEG = 8 | [GM] sai số PWL 0,376% / 0,094% / 0,025% (4/8/16 đoạn); sai số tổng ở 8 đoạn đã bằng sàn lượng tử hoá UINT8 |
| B6 | Không masking | [TL] Lu et al. [9]: masked softmax cần cho attention có mask; [TK] demo không cần, phần mềm có thể đặt phần tử bị mask = −128 |
| B7 | Avalon readLatency cố định, không waitrequest | [ĐC] Intel Avalon Interface Specifications; [TK] 2 chu kỳ = tầng đọc M10K có thanh ghi + tầng mux |
| B7 | Bản đồ thanh ghi, START/DONE polling, 4 phần tử 8 bit/word | [TK] thiết kế của project; tham khảo mẫu một accelerator SpMV trên DE10-Nano (Avalon slave cho thanh ghi HPS, đóng gói 4×INT8/word 32 bit) |
| A1 | 2 bank × 32 bit | [ĐC] Intel Quartus Recommended HDL Coding Styles (template RAM infer); [TK] tránh RAM khác độ rộng hai cổng |
| A2 | Online normalization, IntMax → hiệu chỉnh bằng dịch | [TL] Milakov & Gimelshein [1]; Softermax [3] |
| A2 | Nhanh hơn ~30% so với 3 lượt | [TK] 2·⌈L/P⌉ so với 3·⌈L/P⌉ chu kỳ quét |
| A3 | Không chồng lặp bộ chia | [TL] Softermax [3]: Normalization Unit đặt ngoài đường găng, dùng chung; [TK] thiệt ~28/176 ≈ 16% chu kỳ mỗi hàng (ước lượng) |
| A4 | X/Y tách riêng | [TL] SoftGen [6]: đánh đổi diện tích–tính linh hoạt khi lưu dữ liệu trung gian; [TK] ưu tiên khả năng debug |
| A5 | Tham số P, quét 4/8/16 | [TL] SoftGen [6]: generator tham số hoá để khám phá không gian thiết kế; [TK] |
| — | P = 8: 24 DSP, 1 681 ALUT, 21 M10K, 122–134 MHz qua 3 seed; 182 chu kỳ/hàng ở L = 512; vòng tích luỹ không phải đường găng nhất | Fitter Quartus 18.1 (`syn/fit.sh`) và mô phỏng `CYCLE_CNT`, 2026-11-04; thay ước lượng cũ ~16 DSP, ~176 chu kỳ/hàng |
| D18 | DeiT-Tiny: 197 token, 3 head, 12 layer, ~5M tham số | [TL] DeiT [13] — cần đối chiếu; [ĐC] trọng số `timm` |
| D18 | Không cần mask, có mốc integer-only trên cùng mô hình | [TL] I-ViT [4] báo cáo DeiT-T; [TK] ViT không dùng attention mask → khớp B6 |
| D18 | 104 chu kỳ/hàng, 61 503 chu kỳ mỗi layer mỗi ảnh; ~231 KiB JTAG | chu kỳ: công thức `CYCLE_CNT` đã kiểm bằng mô phỏng; JTAG: [TK], đo bằng băng thông thật |

## 8. Kế hoạch

| Tuần | Khoảng | Mốc | Đầu ra |
|---|---|---|---|
| 1–2 | 10-21 → 11-01 | Đề tài, research, requirements v0.9 | ✅ survey, requirements, golden model |
| 3 | 11-02 → 11-08 | Đóng băng giao diện | requirements v1.0 → giao 2 nhóm ✅; tài liệu block `docs/spec/blocks/*.md` (DRAFT → APPROVED) |
| 4 | 11-09 → 11-15 | RTL khối con | `smx_exp2`, `smx_divider`, `smx_maxtree`, `smx_sumacc` + unit test với vector từ model |
| 5 | 11-16 → 11-22 | RTL lõi | `smx_ctrl`, `smx_csr`, buffer, datapath 2 lượt; `smx_core` khớp golden trên vector ngẫu nhiên qua cổng `acc_*` |
| 6 | 11-23 → 11-29 | Tổng hợp lõi | project `syn/` cho `smx_core`, timing ≥ 100 MHz, báo cáo tài nguyên, quét P (nhóm implement song song làm wrapper + hệ thống JTAG) |
| 7 | 11-30 → 12-06 | Tích hợp | sửa lỗi từ verify, hỗ trợ nhóm implement chạy trên board |
| 8 | 12-07 → 12-13 | Đo đạc | quét P, N_SEG, L; số liệu tài nguyên/Fmax/latency; so sánh thuật toán; đánh giá DeiT-Tiny E1–E3 (`target-workload.md` mục 5) |
| 9 | 12-14 → 12-21 | Báo cáo + demo | phần kiến trúc và phân tích |

## 9. Câu hỏi còn mở

- [x] Duyệt B1–B7 và A1–A5 → requirements v1.0 (2026-10-31).
- [ ] Đã điền tên đề tài vào sheet cho nhóm 6 chưa?
- [ ] Ngày nộp chính xác, có báo cáo giữa kỳ không?
- [ ] Nhóm verify dùng ModelSim Starter hay Questa?
- [ ] Bản GHRD/hệ thống nhóm implement dùng có sẵn JTAG to Avalon Master Bridge không (nếu tự dựng hệ thống tối giản thì thêm IP này).
- [x] Nguồn vector demo: điểm attention trích từ DeiT-Tiny (D18, 2026-10-31). Câu hỏi mở còn lại của workload (tập dữ liệu, cách hiệu chuẩn S, layer demo, băng thông JTAG): `docs/spec/target-workload.md` mục 8.

## 10. Nhật ký

- 2026-10-21: Khởi tạo; chốt kit, toolchain, phạm vi, polling, chính sách IP; đề xuất GEMM systolic → huỷ do trùng; chốt đề tài Softmax (D12).
- 2026-10-31: Khảo sát softmax phần cứng (`docs/research/softmax-survey.md`). Làm rõ K = S·log₂e, sửa thứ tự nhân-trước-max (D13, D14). Viết golden model bit-exact `model/softmax_ref.py`, đo sai số; requirements v0.9 baseline; dựng khung repo cho Claude Code CLI. PROJECT.md viết lại cho đề tài Softmax, nội dung GEMM chuyển vào archive.
- 2026-10-31: Draft kiến trúc top (`docs/spec/architecture.md`). Chốt D15 (Avalon, byteenable, conduit), D16 (demo qua JTAG + System Console, không cần Linux), D17 (Chau làm lõi trước; wrapper và hệ thống thuộc nhóm implement, ghi chú ở `docs/spec/integration-notes.md`). Requirements lên v0.9.1.

- 2026-10-31: Chau duyệt B1–B7, A1–A5 → requirements **v1.0** (đóng băng giao diện, HW_PARAM VERSION = 0x10). Thêm bảng nguồn cho từng quyết định (mục 7.1).

- 2026-10-31: Thiết lập quy trình thiết kế có cổng duyệt (research → architecture → block doc → duyệt → RTL + unit test → tích hợp → tổng hợp): mẫu `docs/spec/blocks/_TEMPLATE.md`, bảng trạng thái `docs/spec/blocks/README.md`, lệnh `/block-doc`, `/block-rtl`. Gộp `smx_xbuf/ybuf` thành một module `smx_buf` dùng hai lần.

- 2026-10-31: Chốt D18 — target workload duy nhất là DeiT-Tiny (Chau duyệt). Cân nhắc 7 phương án (DeiT-Tiny, ViT tự train CIFAR-10, DistilBERT SST-2, BERT/I-BERT, GPT-2 decode, Swin-T, KWT); chọn DeiT-Tiny vì khớp v1.0 nguyên trạng (không mask, L = 197), có mốc I-ViT. Viết `docs/spec/target-workload.md`; thêm DeiT [13] vào tham khảo survey. Requirements và VERSION không đổi. Đóng câu hỏi nguồn vector demo.

- 2026-10-31: `smx_exp2` APPROVED (`docs/spec/blocks/smx_exp2.md`, Q1–Q8): một lane, pipeline 3 tầng (`EXP2_LAT`), M cùng chu kỳ với u, mask lane trong block, N_SEG tham số hoá 4/8/16. Kiểm cấu trúc SV bằng Quartus 18.1 Lite (probe). Viết RTL, testbench, `model/gen_vectors.py`, `tb/run_smx_exp2.sh`, `syn/map_check.sh`; thêm `EXP2_LAT` và bảng PWL N = 4/16 vào `smx_pkg`. Chưa chạy mô phỏng.

- 2026-11-03: Thêm flow mô phỏng `sim/` theo cách tổ chức của repo `risc_v` (milestone 2/3): `Makefile`, `compile.f` = `rtl.f` + `tb.f` + `testcase.f`, chọn test bằng `testname`; thay `tb/run_smx_exp2.sh`. Giữ nguyên bố cục `rtl/`, `tb/`. Khác `risc_v`: test fail thì `make` trả lỗi (kiểm `TB_RESULT: PASS`), và chỉ ghi wave khi `WAVE=1`. `smx_exp2` đạt UT-PASS ở N_SEG = 4, 8, 16 trên ModelSim ASE 10.5b. `syn/map_check.sh smx_exp2 N_SEG=4,8,16` đạt (N_SEG = 8: 93 ALUT, 94 thanh ghi, 1 DSP mỗi lane, chỉ Analysis & Synthesis; chưa có số Fitter/Fmax). Ghi cách dùng flow vào `docs/KNOWLEDGE.md` mục 7.

- 2026-11-03: Chau yêu cầu xây các block còn lại bằng nhiều agent, cả tài liệu lẫn RTL, tự thống nhất phần liên block và lưu việc chưa quyết được. Tạo `docs/spec/cross-block.md` (hợp đồng port, latency, FSM, `CYCLE_CNT`), hai reviewer độc lập phản biện bằng mô hình chu kỳ và probe Quartus; `docs/spec/open-decisions.md` là danh sách cho Chau xem. Tài liệu các block mới chưa được duyệt. `SUM_W` 26 → 25; `smx_pkg` thêm latency các block, `ROW_OVERHEAD`, `DM_W`, bỏ `LANE_IDX_W`, `SEG_W`. `softmax_ref.py` thêm số trung gian và tách hàm, số học không đổi (6000 hàng trùng bản cũ). `sim/` hỗ trợ quét P.

- 2026-11-04: `smx_core` tích hợp xong và qua Fitter. P = 4/8/16 đạt ≥ 100 MHz ở mọi seed đã chạy (sát nhất 107,83 MHz ở P = 16); P = 8 dùng 1 681 ALUT, 24 DSP, 21 M10K, Fmax 122,09–134,41 MHz, lấy góc xấu hơn trong hai góc slow. Đường găng nhất ở P = 8, 16 là tầng 1 `smx_maxtree`, ở P = 8 có `tag_q` bị Quartus chuyển vào M10K, không phải vòng tích luỹ như dự đoán. Rà soát độc lập không tìm ra lỗi số học nhưng chỉ ra `tb_smx_core` bỏ sót mutation về bus khi BUSY và Y cũ che lỗi; đã siết bench, 11/11 mutation bị bắt, `make regress` PASS ở P, N_SEG = 4/8/16. RTL không đổi. Thêm `syn/fit.sh`. Thêm A5–A7 vào `docs/spec/open-decisions.md`. Sửa số chu kỳ DeiT-Tiny theo số đo (104 chu kỳ/hàng, 61 503 chu kỳ/layer).

- 2026-11-05: Chau chốt A2: deassert `rst_n` do test drive, lõi không chứa bộ đồng bộ reset. REQ-IF-04 không đổi; RTL không đổi, testbench đã thả reset ở cạnh xuống của `clk`.

- 2026-11-05: Thêm `docs/spec/design-spec.md`, bản gộp cho `smx_core`: hoạt động từng bước với mốc chu kỳ đo bằng mô phỏng và ví dụ số từ golden model, interface, port, sơ đồ, số đo. Không có quyết định mới. Thêm sơ đồ cấu trúc cho `smx_ctrl`, sửa sơ đồ trong `architecture.md` mục 2 để khớp RTL.

## 11. Tài liệu tham khảo chính

Danh sách đầy đủ ở `docs/research/softmax-survey.md` mục 7. Cốt lõi: Milakov & Gimelshein 2018 (online normalizer); Kim et al., I-BERT, ICML 2021; Stevens et al., Softermax, DAC 2021; Li & Gu, I-ViT/Shiftmax, ICCV 2023; Wei et al., SoftGen, ASAP 2020; Wang et al., log-sum-exp, APCCAS 2018; Wang et al., SOLE, 2025. Tài liệu nền accelerator (Kung 1982, TPU 2017, Eyeriss 2016, Sze 2017, Jacob 2018) ở `docs/archive/gemm-sa-proposal.md` mục tham khảo.
