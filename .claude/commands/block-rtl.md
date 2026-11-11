---
description: Viết RTL + unit test cho một block đã được duyệt tài liệu
argument-hint: <block_name>
---
Hiện thực block `$ARGUMENTS`.

1. Kiểm cổng duyệt: mở `docs/spec/blocks/$ARGUMENTS.md` và `docs/spec/blocks/README.md`. Nếu trạng thái **không phải `APPROVED`**, dừng lại, báo người dùng và không viết code.
2. Viết `rtl/core/$ARGUMENTS.sv` đúng port, latency, số học trong tài liệu và quy ước SystemVerilog Quartus 18.1 trong `CLAUDE.md`.
3. Nếu block có số học: viết `model/vec_<block>.py` (`gen_vectors.py` tự nhận), số học gọi từ `model/softmax_ref.py`; vector nằm ở `tb/vectors/<module>/p<P>_n<N>/`. Hợp đồng chung: `docs/spec/05-cross-block.md`.
4. Viết `tb/tb_$ARGUMENTS.sv` tự kiểm: đọc vector, so bit-exact, in PASS/FAIL và số lỗi.
5. Thêm file vào `scripts/rtl.f` và `scripts/testcase.f`, chạy mô phỏng theo `/sim $ARGUMENTS` và `syn/map_check.sh $ARGUMENTS` nếu có công cụ; báo kết quả thật, không đoán. Không viết script chạy riêng.
6. Nếu RTL buộc phải lệch tài liệu: dừng, nêu lý do, đề xuất sửa tài liệu — không âm thầm lệch.
7. Cập nhật trạng thái `RTL` hoặc `UT-PASS` trong `docs/spec/blocks/README.md`.
