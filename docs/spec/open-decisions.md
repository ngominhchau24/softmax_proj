# Open decisions — danh sách để Chau xem

> Ghi trong lúc xây các block còn lại theo ủy quyền của Chau ngày 2026-11-03. Phần A cần Chau quyết. Phần B là việc đã tự quyết để không dừng công việc, đảo ngược được; Chau chỉ cần xem lướt và phản đối nếu không đồng ý.

## A. Cần Chau quyết

- [ ] **A1. Duyệt tài liệu block.** Theo yêu cầu của Chau, RTL được viết trước cổng duyệt. Các block mới không mang trạng thái `APPROVED`; tài liệu ghi "chưa Chau duyệt". Chau đọc rồi xác nhận từng block hoặc yêu cầu sửa.
- [ ] **A2. Bộ đồng bộ reset (REQ-IF-04).** Yêu cầu nói `rst_n` assert bất đồng bộ, deassert đồng bộ, nhưng không nói ai làm phần deassert. Đề xuất: lõi không chứa bộ đồng bộ, dựa vào reset controller của Platform Designer, và ghi vào `integration-notes.md`. Việc này ảnh hưởng nhóm implement nên cần Chau xác nhận.
- [ ] **A3. Sửa câu trong REQ-ARI-05 (requirements đóng băng).** Câu "`sum` không dấu, ≥ 25 bit (≤ 512·2¹⁶)" có cận 2²⁵, cần 26 bit. Cận đúng và đã đo là `L_MAX·2¹⁵ = 2²⁴`, cần 25 bit. Không ảnh hưởng số học hay giao diện. Đề xuất sửa thành "≤ 512·2¹⁵".
- [ ] **A4. Span Platform Designer (bàn giao nhóm implement, chưa kiểm).** Cổng 13 bit word address có thể khiến Platform Designer gán span 0x8000 thay vì 0x6000 trong requirements 5.2. Lõi không bị ảnh hưởng vì vùng `0x1800..0x1FFF` đọc 0. Đề xuất ghi một dòng vào `integration-notes.md` để nhóm implement kiểm.

## B. Đã tự quyết (đảo ngược được)

- **B1.** `SUM_W` từ 26 xuống 25. `E ≤ 2¹⁵` nên `sum ≤ L_MAX·2¹⁵ = 2²⁴`; đạt 2²⁴ ở `K = 0, L = 512` [GM]. Requirements chỉ đòi ≥ 25 bit.
- **B2.** Kiểm LEN, ROWS nằm ở `smx_csr`, không có trạng thái CHECK trong FSM. START sai thì BUSY không lên và `CYCLE_CNT = 0`. Sơ đồ FSM trong `architecture.md` được cập nhật theo; bảng block ở đó vốn đã ghi việc kiểm thuộc `smx_csr`.
- **B3.** Khi BUSY, ghi LEN, ROWS, SCALE_K, X_BUF bị bỏ qua. REQ-IF-09 để không xác định nên được phép chọn.
- **B4.** `smx_buf` có `BANKS = P/4` để quét được P = 4/8/16 (A5). P = 8 đúng bằng A1.
- **B5.** Latency chốt ở `smx_pkg`, `T_row = 2G + 54`, `CYCLE_CNT = R·(2G + 54) + 1`. Là số thiết kế; xác nhận bằng mô phỏng ở bước tích hợp.
- **B6.** `model/softmax_ref.py` thêm trường trung gian vào `info` và tách `group_sum`, `reciprocal`, `norm_out`. Không đổi số học: 6000 hàng ngẫu nhiên và corner ở P, N_SEG = 4/8/16 cho kết quả trùng bản cũ.
- **B7.** Bộ chia dùng so sánh 25 bit và 27 vòng lặp, thay vì ~41 bit như bảng ước lượng trong `architecture.md`. Kết quả vẫn bit-exact vì `2¹⁴ ≤ sum ≤ 2²⁴`.
- **B8.** Chia tầng `smx_maxtree` để tầng 2 chứa mức cuối của cây, so với M và `dm`. Kết quả từ Fitter trên probe: gom cả cây vào tầng 1 chỉ đạt 90 MHz ở P = 16.
- **B9.** `smx_delay` không có tài liệu block và testbench riêng vì chỉ vài dòng; kiểm qua testbench `smx_core`.
- **B10.** Dạng assertion REQ-VER-03 cho nhóm verify: `$rose(done) |-> !busy`, không phải `|-> $fell(busy)`; assertion "không có X trên `readdata`" chỉ áp dụng cho vị trí đã ghi (`cross-block.md` mục 4.8).
