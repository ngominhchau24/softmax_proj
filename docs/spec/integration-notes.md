# Integration notes — bàn giao cho nhóm implement

> Phần này **không** thuộc ưu tiên hiện tại của người thiết kế RTL (lõi trước). Ghi lại để nhóm implement làm tiếp. Hợp đồng chính thức: `docs/requirements.md` mục 5. Có thắc mắc về giao diện → hỏi trước khi đổi, vì bản đồ thanh ghi là hợp đồng chung.

## 1. Việc của nhóm implement

1. `rtl/avalon/smx_avalon.sv`: wrapper mỏng, nối `acc_*` của `smx_core` với Avalon slave `s0` (đổi tên tín hiệu, không thêm logic; read latency 2 giữ nguyên).
2. `ip/smx_hw.tcl`: component Platform Designer theo REQ-IF-11 (clock, reset_n, slave `s0` WORDS / readLatency 2 / không waitrequest / không burst / byteenable 4 bit, conduit `status`).
3. Hệ thống Platform Designer cho demo, không HPS: Clock Source (CLOCK_50, reset từ một nút KEY), JTAG to Avalon Master Bridge, `smx`. Top-level Quartus gán chân DE10-Standard (CLOCK_50, KEY, LEDR) — đối chiếu file pin/QSF của Terasic.
4. Script demo: Python dùng `model/softmax_ref.py` sinh vector + kết quả kỳ vọng, sinh Tcl cho System Console (`master_write_32`, `master_read_32`), chạy, đọc Y_BUF và CYCLE_CNT, so sánh và in kết quả.
5. (Tuỳ chọn) Tích hợp vào GHRD có HPS + Linux.

## 2. Lưu ý

- **Không dùng GHRD khi không boot Linux.** Trong GHRD, reset phía FPGA thường gắn với reset do HPS phát và các bridge chỉ bật khi phần mềm HPS cấu hình; nếu HPS không chạy, logic FPGA có thể bị giữ reset (tuỳ phiên bản, cần kiểm tra). Hệ thống demo nên không có HPS.
- **Địa chỉ:** qua JTAG master dùng base do Platform Designer gán (ví dụ 0x0) + offset trong requirements 5.2. Qua HPS là `0xFF200000 + base` (đối chiếu tài liệu Terasic).
- **Băng thông JTAG** thấp (cỡ chục–trăm KB/s) nhưng đủ: mỗi lần chạy ≤ 8 KB. Thời gian tính đo bằng `CYCLE_CNT`, không phụ thuộc JTAG.
- **Byteenable** được hỗ trợ, nhưng Tcl nên ghi nguyên word cho nhanh.
- **Reset:** `smx_core` không có bộ đồng bộ reset. `rst_n` được assert bất đồng bộ, nhưng phải deassert đồng bộ với `clk` (REQ-IF-04), và đây là trách nhiệm của bên lái `rst_n`.
- **Conduit `status`** nối 3 LED (busy/done/err) để người xem thấy accelerator chạy.
- **Thuật ngữ:** golden model = `model/softmax_ref.py`; GHRD = thiết kế mẫu Terasic.

## 3. Ví dụ System Console (phác thảo, cần chỉnh theo hệ thống thật)

```tcl
set m [lindex [get_service_paths master] 0]
open_service master $m
set BASE 0x0
master_write_32 $m [expr $BASE + 0x0010] 5909        ;# SCALE_K
master_write_32 $m [expr $BASE + 0x0008] 512         ;# LEN
master_write_32 $m [expr $BASE + 0x000C] 1           ;# ROWS
# ... ghi X_BUF tại BASE + 0x2000 ...
master_write_32 $m [expr $BASE + 0x0000] 1           ;# START
while {([master_read_32 $m [expr $BASE + 0x0004] 1] & 0x2) == 0} {}
set y [master_read_32 $m [expr $BASE + 0x4000] 128]  ;# 512 byte Y
set cyc [master_read_32 $m [expr $BASE + 0x0014] 1]
close_service master $m
```
