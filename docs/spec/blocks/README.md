# Block tracker — `smx_core`

Mỗi block có một tài liệu `docs/spec/blocks/<block>.md` theo `_TEMPLATE.md`. Quy trình và cổng duyệt: `CLAUDE.md` mục "Quy trình thiết kế".

Trạng thái: `TODO` → `DRAFT` → `REVIEW` → `APPROVED` → `RTL` → `UT-PASS` (unit test khớp golden) → `INTEGRATED`.
**Không viết RTL cho block chưa `APPROVED`.** Đổi trạng thái thì cập nhật bảng này cùng lúc.

| # | Block | Vai trò | Phụ thuộc | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| 1 | `smx_exp2` | d = u − M·2¹⁶ → E (PWL + shift) | smx_pkg | UT-PASS | 2026-11-03 `make regress` trong `sim/` PASS ở N_SEG = 4, 8, 16 (ModelSim ASE 10.5b); `syn/map_check.sh smx_exp2 N_SEG=4,8,16` đạt, chưa có số Fitter/Fmax |
| 2 | `smx_scale` | u = q·K, c = ⌈u⌉ | — | TODO | |
| 3 | `smx_maxtree` | Mg, cập nhật M | smx_scale | TODO | vòng phản hồi M |
| 4 | `smx_sumacc` | cây cộng + tích luỹ có renorm | smx_exp2, smx_maxtree | TODO | đường găng timing |
| 5 | `smx_divider` | ⌊2⁴⁰/sum⌋ tuần tự | — | TODO | |
| 6 | `smx_norm` | E·Rcp, round, sat | smx_divider | TODO | |
| 7 | `smx_buf` | 2 bank × 32 bit, byte-en; dùng cho X và Y | — | TODO | template RAM Intel |
| 8 | `smx_csr` | thanh ghi, START/DONE/ERR, CYCLE_CNT, decode `acc_*` | smx_pkg | TODO | hợp đồng giao diện |
| 9 | `smx_ctrl` | FSM hàng/lượt, địa chỉ, lane mask | tất cả trên | TODO | |
| 10 | `smx_core` | top lõi, nối các block | tất cả | TODO | |
