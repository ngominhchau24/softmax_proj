# smx — Integer-Only Softmax Accelerator for Transformer Attention

BTL môn Cấu trúc phần cứng cho giải thuật học máy (nhóm 6), hạn nộp khoảng **2026-12-21**. IP Avalon-MM slave trên Cyclone V (DE10-Standard, 5CSXFC6D6F31C6) tính softmax theo hàng cho điểm attention INT8, ra UINT8 (scale 1/256). Số học thuần số nguyên; workload mục tiêu là softmax trong self-attention của DeiT-Tiny (L = 197). Demo trên board qua JTAG + System Console, không cần Linux.

## Đang ở đâu (cập nhật 2026-11-06)

| Phần | Trạng thái |
|---|---|
| Lõi `smx_core` (RTL) | **Xong.** 10 block + `smx_delay`, khớp golden model bit-exact. |
| Kiểm thử lõi | `tb_smx_core` PASS ở P và N_SEG = 4/8/16; 11/11 mutation bị bắt ở P = N_SEG = 8. |
| Tổng hợp | Fitter đạt ≥ 100 MHz. P = 8: 1 681 ALUT, 24 DSP, 21 M10K, 122–134 MHz qua 3 seed. Số đầy đủ ở `docs/spec/blocks/smx_core.md` mục 6, 7. |
| Tài liệu thiết kế | Xong nhưng **DRAFT**: người thiết kế chưa duyệt (`docs/spec/07-open-decisions.md` mục A). Chỉ `smx_exp2` là `APPROVED`. |
| Wrapper Avalon, Platform Designer, System Console | **Chưa làm** (`rtl/avalon/`, `ip/`, `sw/` còn trống). Đây là việc của phần board. |
| Verification chính thức | **Chưa làm.** Mới có testbench tự kiểm của người thiết kế. |
| Báo cáo | Mới có khung LaTeX (`docs/report/`), nội dung chưa viết. |

Trạng thái chi tiết, việc đang chờ và việc kế tiếp: **`docs/PROGRESS.md`** (đọc file này đầu tiên).

`main` trùng với nhánh `rtl/smx-core`; mọi nhánh khác đã được gộp.

## Việc cho người nhận bàn giao

Ba mảng, mỗi mảng có điểm vào riêng. Mọi con số đưa vào báo cáo hay tài liệu phải đến từ mô phỏng hoặc báo cáo Quartus thật, và ghi loại nguồn ([TL] tài liệu, [GM] golden model, [TK] thiết kế/ước lượng, [ĐC] cần đối chiếu).

**Báo cáo.**
- Khung và quy ước: `docs/report/`, `docs/CONVENTIONS.md`. Biên dịch bằng XeLaTeX.
- Nội dung lấy từ `docs/spec/` (kiến trúc, từng block, lý thuyết) và `docs/research/softmax-survey.md` (tài liệu tham khảo).
- Số liệu chưa đo ghi `[Chưa đo]`. Còn thiếu: thêm seed ở P = 4, Fitter ở N_SEG = 4 và 16, đánh giá DeiT-Tiny E1–E3 (`docs/spec/02-target-workload.md` mục 5).

**Verification (DV).**
- Giao diện cần kiểm là cổng `acc_*` của `smx_core` (REQ-IF-06), không cần bus Avalon. Danh mục kiểm tra: `docs/requirements.md` (REQ-VER-02, REQ-VER-03).
- Scoreboard: `model/softmax_ref.py`. Vector sinh bằng `model/gen_vectors.py` và `model/vec_*.py`.
- Testbench có sẵn trong `tb/` dùng làm mẫu. Assertion/SVA đặt trong `tb/` hoặc file `*_bind.sv` riêng.
- Câu hỏi mở: dùng ModelSim Starter hay Questa. Lỗi tìm được báo lại cho người thiết kế RTL.

**Board.**
- Việc cần làm và giao diện: `docs/spec/08-integration-notes.md`, `docs/requirements.md` mục 5 (bản đồ thanh ghi, **hợp đồng đã đóng băng**, đổi thì phải tăng `HW_PARAM.VERSION`).
- Cần viết: `rtl/avalon/smx_avalon.sv` (đổi tên `acc_*` ↔ Avalon `s0`, không thêm logic), `ip/smx_hw.tcl`, hệ thống Platform Designer (JTAG to Avalon Master Bridge + `smx`), script System Console, đo băng thông JTAG.
- Lưu ý chờ quyết định (A4, A6, A7 trong `07-open-decisions.md`): span địa chỉ 0x8000, LEN/ROWS vượt trường không báo ERR, ràng buộc timing `acc_*`; reset phải do bên lái `rst_n` thả đồng bộ.

## Thứ tự đọc

1. `docs/PROGRESS.md`: đang ở đâu, chờ gì.
2. `docs/KNOWLEDGE.md`: bản nén thuật toán, tham số, thanh ghi, quy tắc cứng. Đủ cho phần lớn công việc.
3. `docs/spec/`: đọc theo số thứ tự file (bảng dưới).
4. `docs/PROJECT.md` và `docs/requirements.md`: khi cần quyết định gốc, bảng nguồn số liệu, REQ-* chi tiết.
5. `model/softmax_ref.py`: nguồn chân lý về số học.

| File trong `docs/spec/` | Nội dung |
|---|---|
| `01-softmax-theory.md` | Từ lý thuyết softmax đến phương trình phần cứng |
| `02-target-workload.md` | DeiT-Tiny và cách đánh giá |
| `03-design-spec.md` | Spec gộp, đọc một lượt từ đầu đến cuối |
| `04-architecture.md` | Kiến trúc mức top |
| `05-cross-block.md` | Hợp đồng port và pipeline giữa các block |
| `blocks/` | Mỗi block một tài liệu; bảng trạng thái ở `blocks/README.md` |
| `07-open-decisions.md` | Các quyết định còn chờ |
| `08-integration-notes.md` | Bàn giao cho phần board |
| `09-diagram-rules.md` | Quy tắc vẽ sơ đồ |

## Cấu trúc thư mục

```
README.md               file này
docs/
  PROGRESS.md           trạng thái hiện tại, việc chờ, việc kế tiếp
  KNOWLEDGE.md          bản nén để đọc đầu phiên
  PROJECT.md            nền tảng, quyết định (D-mã), nguồn số liệu, nhật ký
  requirements.md       REQ-*, số học, bản đồ thanh ghi (v1.0, đóng băng)
  CONVENTIONS.md        quy ước báo cáo, hình, công cụ
  research/             khảo sát tài liệu (softmax-survey.md)
  spec/                 01–09 như bảng trên
    blocks/             tài liệu từng block theo _TEMPLATE.md
    fig/                sơ đồ: <tên>.py sinh <tên>.svg
    wave/               dạng sóng WaveDrom JSON
  report/               báo cáo LaTeX (main.tex, chapters/)
  figures/              hình đưa vào báo cáo
  archive/              tài liệu đã huỷ (đề xuất GEMM), không dùng làm định hướng
model/                  golden model softmax_ref.py, sinh vector (gen_vectors.py, vec_*.py)
rtl/
  pkg/                  smx_pkg.sv, bảng PWL (pwl_n8.hex, sinh bằng model, không sửa tay)
  core/                 smx_core và các block con
  avalon/               wrapper Avalon (chưa có, phần board)
tb/                     testbench tự kiểm; tb/vectors/ do script sinh, không đưa lên git
sim/                    flow mô phỏng ModelSim/Questa: Makefile, chạy từ thư mục này
scripts/                file cho bước compile: rtl.f, tb.f, testcase.f, compile.f, setup.sh (trỏ flow tới ModelSim)
syn/                    script tổng hợp: fit.sh (Fitter nhiều seed), map_check.sh
ip/                     smx_hw.tcl (chưa có, phần board)
sw/                     mã host tham khảo (chưa có)
```

## Lệnh hay dùng

```bash
python3 model/softmax_ref.py --selftest          # kiểm model và đo sai số (cần Python 3 + NumPy)
cd sim && make testname=tb_smx_core P=8 N_SEG=8  # một test, khoảng 30 s, phải có TB_RESULT: PASS
cd sim && make regress                           # compile và chạy N_SEG = 4 8 16
cd sim && make run WAVE=1                        # chạy lại không compile, ghi wave
```

Block mới thì thêm vào `scripts/rtl.f` và `scripts/testcase.f`. Chi tiết flow: `docs/KNOWLEDGE.md` mục 7. Tổng hợp: `syn/fit.sh`, `syn/map_check.sh` (cần Quartus Prime Lite 18.1).

## Quy tắc không được vi phạm

1. **Số học bit-exact** với `model/softmax_ref.py`. Muốn đổi: sửa model trước, cập nhật `docs/requirements.md` mục 4, ghi Nhật ký trong `docs/PROJECT.md`, rồi mới sửa RTL.
2. **Giao diện** (bản đồ thanh ghi, bố trí buffer) là hợp đồng giữa các nhóm; đổi thì tăng `HW_PARAM.VERSION` và ghi Nhật ký.
3. **Requirements v1.0 đã đóng băng.** Muốn đổi phải hỏi người thiết kế RTL và ghi Nhật ký.
4. **Phạm vi đề tài:** không thêm GEMM, convolution hay biến thành "activation accelerator".
5. **Không bịa số liệu:** tài nguyên, Fmax, latency chỉ lấy từ Quartus hoặc mô phỏng thật.

## Dùng Claude Code trong repo này

Mọi phiên nên bắt đầu bằng việc đọc `docs/PROGRESS.md`, rồi `docs/KNOWLEDGE.md`, đúng thứ tự ở trên; các file này nằm trên git. `CLAUDE.md` (quy trình thiết kế, quy ước SystemVerilog, quy tắc cứng, mục "Vai trò" cho người nhận bàn giao) và `.claude/commands/` (`/block-doc`, `/block-rtl`, `/sim`) cũng nằm trên git, nên Claude Code tự nạp khi mở repo. Cấu hình quyền cục bộ `.claude/settings.json` thì không (đã ignore); tự tạo theo máy của mình.
