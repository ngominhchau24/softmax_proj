---
description: Viết hoặc cập nhật tài liệu thiết kế cho một block (chưa viết RTL)
argument-hint: <block_name>
---
Viết tài liệu thiết kế cho block `$ARGUMENTS`.

1. Đọc `CLAUDE.md`, `docs/requirements.md`, `docs/spec/04-architecture.md`, `docs/spec/blocks/README.md`, và các tài liệu block mà `$ARGUMENTS` phụ thuộc.
2. Đọc phần tương ứng trong `model/softmax_ref.py`; mọi công thức trong tài liệu phải khớp từng bước với model.
3. Tạo/cập nhật `docs/spec/blocks/$ARGUMENTS.md` theo đúng `docs/spec/blocks/_TEMPLATE.md`: đủ 10 mục, sơ đồ cấu trúc bên trong theo `docs/spec/09-diagram-rules.md` (dây vuông góc, script trong `docs/spec/fig/`), dạng sóng WaveDrom ở `docs/spec/wave/$ARGUMENTS.json`.
4. Số liệu ước lượng ghi nhãn [TK]; không bịa số tổng hợp.
5. Đặt trạng thái `DRAFT` trong tài liệu và trong `docs/spec/blocks/README.md`.
6. **Không tạo file RTL.** Kết thúc bằng danh sách câu hỏi mở cần người dùng duyệt.
