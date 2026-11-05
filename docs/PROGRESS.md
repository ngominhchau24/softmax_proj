# PROGRESS — đang ở đâu, chờ gì, làm gì tiếp

> Đọc đầu phiên, trước khi bắt đầu việc. Cập nhật file này trong cùng commit khi trạng thái đổi: xong một việc, có quyết định mới, hoặc có việc mới phải chờ. Chỉ ghi trạng thái hiện tại; lịch sử nằm ở `git log` và `docs/PROJECT.md` mục 10.

**Cập nhật lần cuối:** 2026-11-05. **Nhánh:** `rtl/smx-core`, đã push, chưa có PR vào `main`.

## Trạng thái

RTL `smx_core` đã tích hợp và qua Fitter. Tài liệu vẫn là DRAFT, nên cổng duyệt còn nợ.

| Hạng mục | Trạng thái | Ở đâu |
|---|---|---|
| RTL 10 block + `smx_delay` | Xong, khớp golden | `rtl/core/`, `docs/spec/blocks/README.md` |
| `tb_smx_core` | PASS ở P, N_SEG = 4/8/16; 11/11 mutation bị bắt ở P = N_SEG = 8 | `tb/tb_smx_core.sv`, `model/vec_core.py` |
| Fitter | Đạt ≥ 100 MHz; P = 8 và 16 chạy 3 seed, P = 4 chạy 1 seed, N_SEG = 8 | `syn/fit.sh`, `docs/spec/blocks/smx_core.md` mục 6, 7 |
| Spec gộp | Xong, DRAFT | `docs/spec/design-spec.md` |
| Trang tổng quan | Đã publish, riêng tư | https://claude.ai/artifact/3DFqbxKoc9vqgVEwhHirCx |

Chưa có gì trong `rtl/avalon/`, `ip/`, `sw/`: wrapper và hệ thống thuộc nhóm implement, không tự viết (`CLAUDE.md`).

## Đang chờ Chau

Đừng tự quyết các mục này. Chi tiết và đề xuất: `docs/spec/open-decisions.md` phần A.

| Mục | Cần gì | Việc phải làm sau khi có trả lời |
|---|---|---|
| A1 | Duyệt `design-spec.md` và 9 tài liệu block, trừ `smx_exp2` đã `APPROVED` | Chỉ khi Chau xác nhận mới đổi sang `APPROVED`, rồi cập nhật tracker |
| A3 | Có sửa cận `sum` trong REQ-ARI-05 thành `≤ 512·2¹⁵` không | Sửa `requirements.md` mục 4, ghi Nhật ký, cập nhật mục 7.1 của `PROJECT.md` |
| A4 | Có ghi lưu ý span 0x8000 không | Thêm vào `integration-notes.md` |
| A5 | Giữ `tag_q` trong M10K không; đề xuất giữ | Nếu đổi: sửa RTL, chạy lại regress và Fitter |
| A6 | Có ghi lưu ý LEN, ROWS vượt trường không báo ERR không | Thêm vào `integration-notes.md` |
| A7 | Có ghi yêu cầu ràng buộc timing `acc_*` không | Thêm vào `integration-notes.md` |

Câu hỏi khác đang chờ Chau:

- **Reset trên board:** A2 đã chốt là deassert do test drive, lõi không có bộ đồng bộ. `integration-notes.md` đang tạm ghi trên hệ thống thật là trách nhiệm của bên lái `rst_n`; chưa xác nhận.
- **Worktree cũ:** có xoá 9 worktree đã merge trong `.claude/worktrees` (98 MB) không. Chưa xoá.
- **PR vào `main`:** chỉ mở khi Chau yêu cầu.
- **Tài liệu trên claude.ai:** nhắc Chau tải lại docs lên Project; repo không tự đồng bộ.
- **Đề tài và lịch:** tên đề tài trong sheet nhóm 6, ngày nộp chính xác (`PROJECT.md` mục 9).
- **Đánh giá DeiT-Tiny:** tập dữ liệu, cách hiệu chuẩn S, layer chạy trên board (`target-workload.md` mục 8).

## Đang chờ nhóm khác

- **Nhóm implement:** `smx_avalon`, `ip/smx_hw.tcl`, hệ thống Platform Designer, script System Console, đo băng thông JTAG. Câu hỏi còn mở: họ dùng JTAG to Avalon Master Bridge không.
- **Nhóm verify:** verification chính thức, assertion REQ-VER-03. Câu hỏi còn mở: dùng ModelSim Starter hay Questa. Lỗi họ báo sẽ quay về RTL.

## Việc tiếp theo

Theo thứ tự, khi Chau không chỉ định khác. Lịch ở `PROJECT.md` mục 8.

1. Áp dụng các trả lời ở bảng trên, cập nhật `open-decisions.md` và `integration-notes.md`.
2. Rà sâu `smx_scale`, `smx_exp2`, `smx_norm` và đối chiếu tài liệu từng block với RTL. Phần này chưa làm xong: báo cáo của reviewer độc lập bị mất; port và hướng đã so bằng script, độ rộng thì chưa.
3. Quét số đo cho báo cáo: thêm seed ở P = 4, chạy Fitter ở N_SEG = 4 và 16, ghi số vào `smx_core.md`.
4. Đánh giá DeiT-Tiny bằng golden model: E1, E2 (`target-workload.md` mục 5), sau khi có trả lời ở trên.
5. Hỗ trợ nhóm implement chạy trên board và E3 khi họ sẵn sàng.
6. Báo cáo và demo, hạn khoảng 2026-12-21.

## Lưu ý vận hành

- **Git:** commit và push sau mỗi bước đã kiểm chứng, trên nhánh làm việc; không push thẳng `main`.
- **Tác vụ tự chạy tiếp:** "Resume softmax core work after quota" đang **tắt**, và gắn với phiên cũ `session_018kvwhthqKq5fC6j8brjM6B`. Phiên mới cần cơ chế này thì tạo tác vụ mới. Nó chỉ chạy khi máy bật và phiên còn sống.
- **`/tmp` mất khi tắt máy:** bench riêng của reviewer và script dựng trang tổng quan đều nằm ở đó, không có trong repo. Đừng tìm lại. Muốn sửa trang: dùng `Artifact` `action: read` với URL ở trên rồi publish lại vào cùng URL.
- **Máy này không có browser** cho `mmdc` và Playwright. Sơ đồ mermaid mới chỉ được kiểm cú pháp, chưa xem hình.
- **Trang tổng quan là bản chụp:** khi spec đổi đáng kể thì publish lại.

## Kiểm tra nhanh đầu phiên

```bash
git status -sb && git log --oneline -5
cd sim && make testname=tb_smx_core P=8 N_SEG=8      # khoảng 30 s, phải có TB_RESULT: PASS
```
