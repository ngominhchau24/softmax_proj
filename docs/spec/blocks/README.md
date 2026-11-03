# Block tracker — `smx_core`

Mỗi block có một tài liệu `docs/spec/blocks/<block>.md` theo `_TEMPLATE.md`. Quy trình và cổng duyệt: `CLAUDE.md` mục "Quy trình thiết kế".

Trạng thái: `TODO` → `DRAFT` → `REVIEW` → `APPROVED` → `RTL` → `UT-PASS` (unit test khớp golden) → `INTEGRATED`.
**Không viết RTL cho block chưa `APPROVED`.** Đổi trạng thái thì cập nhật bảng này cùng lúc.

Ngoại lệ ngày 2026-11-03: theo yêu cầu của Chau, các block còn lại được viết cả tài liệu lẫn RTL trước cổng duyệt. Cột Trạng thái ghi tiến độ RTL; tài liệu các block này **chưa được duyệt** (`docs/spec/open-decisions.md` A1). Hợp đồng chung: `docs/spec/cross-block.md`.

| # | Block | Vai trò | Phụ thuộc | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| 1 | `smx_exp2` | d = u − M·2¹⁶ → E (PWL + shift) | smx_pkg | UT-PASS | 2026-11-03 `make regress` trong `sim/` PASS ở N_SEG = 4, 8, 16 (ModelSim ASE 10.5b); `syn/map_check.sh smx_exp2 N_SEG=4,8,16` đạt, chưa có số Fitter/Fmax |
| 2 | `smx_scale` | u = q·K, c = ⌈u⌉ | — | UT-PASS | exhaustive q × K tập chọn, 114 112 phần tử; `map_check` 1 lane: 13 ALUT, 85 FF, 1 DSP; chỉ Analysis & Synthesis, chưa có Fitter |
| 3 | `smx_maxtree` | Mg, cập nhật M | smx_scale | UT-PASS | P = 4/8/16; `map_check` P = 8: 202 ALUT, 38 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 4 | `smx_sumacc` | cây cộng + tích luỹ có renorm | smx_exp2, smx_maxtree | UT-PASS | P = 4/8/16, gồm `sum = 2²⁴`; `map_check` P = 8: 180 ALUT, 101 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 5 | `smx_divider` | ⌊2⁴⁰/sum⌋ tuần tự | — | UT-PASS | 40 786 phép chia; `map_check`: 60 ALUT, 109 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 6 | `smx_norm` | E·Rcp, round, sat | smx_divider | UT-PASS | 153 126 phần tử; `map_check` 1 lane: 20 ALUT, 66 FF, 1 DSP; chỉ Analysis & Synthesis, chưa có Fitter |
| 7 | `smx_buf` | 2 bank × 32 bit, byte-en; dùng cho X và Y | — | UT-PASS | P = 4/8/16; `map_check`: 65 536 bit block memory, 0 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 8 | `smx_csr` | thanh ghi, START/DONE/ERR, CYCLE_CNT, decode `acc_*` | smx_pkg | UT-PASS | P, N_SEG = 4/8/16; `map_check` P = 8: 192 ALUT, 136 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 9 | `smx_ctrl` | FSM hàng/lượt, địa chỉ, lane mask | tất cả trên | UT-PASS | 271 tổ hợp L, R ở mỗi P; `map_check` P = 8: 72 ALUT, 24 FF; chỉ Analysis & Synthesis, chưa có Fitter |
| 10 | `smx_core` | top lõi, nối các block | tất cả | TODO | |
| — | `smx_delay` | tiện ích trễ dữ liệu | — | RTL | không có tài liệu riêng (`cross-block.md` mục 4.10); kiểm qua testbench `smx_core` |
