---
description: Compile và chạy mô phỏng một block qua flow chung ở sim/
argument-hint: <block_name>
---
Mô phỏng block `$ARGUMENTS`. Cách dùng flow, quy ước và các giả định của `Makefile`: `docs/KNOWLEDGE.md` mục 7.

1. Kiểm `scripts/rtl.f` và `scripts/testcase.f` đã có file của block; thiếu thì thêm (`smx_pkg.sv` đầu tiên, khối con trước khối cha).
2. Chạy từ `sim/`: `make regress testname=tb_$ARGUMENTS`. Nếu testbench không có tham số `N_SEG`, chạy `make testname=tb_$ARGUMENTS`. Nếu đã đổi model hoặc `model/gen_vectors.py`, thêm `REGEN=1`.
3. Đọc mã thoát của `make` và dòng `TB_RESULT` trong `sim/log/`. Báo kết quả thật, gồm số phần tử đã kiểm; không kết luận chỉ từ một phần log.
4. Test fail: xem các dòng `ERROR` trong log, tìm nguyên nhân và báo người dùng. Không sửa số học để cho khớp, không nới testbench để cho qua (`CLAUDE.md`, quy tắc 1).
5. Đạt ở mọi tham số yêu cầu: đổi trạng thái sang `UT-PASS` trong `docs/spec/blocks/README.md`, ghi Lịch sử của tài liệu block và Nhật ký `docs/PROJECT.md`.

`make dump` và `make view` mở GUI nên chỉ dùng khi người dùng cần xem sóng; trong phiên tự động dùng `make run WAVE=1`.
