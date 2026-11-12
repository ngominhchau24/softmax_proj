# PROGRESS — đang ở đâu, chờ gì, làm gì tiếp

> Đọc đầu phiên, trước khi bắt đầu việc. Cập nhật file này trong cùng commit khi trạng thái đổi: xong một việc, có quyết định mới, hoặc có việc mới phải chờ. Chỉ ghi trạng thái hiện tại; lịch sử nằm ở `git log` và `docs/PROJECT.md` mục 10.

**Cập nhật lần cuối:** 2026-11-06. A3 đã duyệt và áp dụng; các file trong `docs/spec/` đã đánh số 01–09 theo thứ tự đọc. **Nhánh:** `main` đã fast-forward lên `rtl/smx-core`; mọi nhánh khác đã được gộp. RTL, số học và bản đồ thanh ghi không đổi kể từ commit tích hợp `ea2f8cd`.

## Phiên gần nhất dừng ở đâu

Không có việc nào đang làm dở: mọi thay đổi đã commit và push, không có tác vụ nền. Phiên 2026-11-05 kết thúc sau khi chuyển xong sơ đồ sang kiểu vuông góc. Bước tiếp theo thuộc về Chau: đọc `docs/spec/01-softmax-theory.md`, rồi trả lời các mục A ở dưới. Khi bắt đầu phiên mới, hỏi Chau đã đọc tới đâu và có trả lời nào chưa, đừng tự chuyển sang việc khác.

## Trạng thái

RTL `smx_core` đã tích hợp và qua Fitter. Tài liệu vẫn là DRAFT, nên cổng duyệt còn nợ.

| Hạng mục | Trạng thái | Ở đâu |
|---|---|---|
| RTL 10 block + `smx_delay` | Xong, khớp golden | `rtl/core/`, `docs/spec/blocks/README.md` |
| `tb_smx_core` | PASS ở P, N_SEG = 4/8/16; 11/11 mutation bị bắt ở P = N_SEG = 8 | `tb/tb_smx_core.sv`, `model/vec_core.py` |
| Fitter | Đạt ≥ 100 MHz; P = 8 và 16 chạy 3 seed, P = 4 chạy 1 seed, N_SEG = 8 | `syn/fit.sh`, `docs/spec/blocks/smx_core.md` mục 6, 7 |
| Spec gộp | Xong, DRAFT | `docs/spec/03-design-spec.md` |
| Trang tổng quan | Đã publish, riêng tư, đã có hình mới | https://claude.ai/artifact/3DFqbxKoc9vqgVEwhHirCx |
| Sơ đồ | Xong: mọi sơ đồ cấu trúc và FSM đã chuyển, Chau đã duyệt kiểu vẽ | `docs/spec/09-diagram-rules.md`, `docs/spec/fig/` (14 hình), hình mẫu https://claude.ai/artifact/KdXrpjvPAcWa2vqQCf61E3 |
| Tài liệu lý thuyết softmax | Xong, Chau đang đọc trước khi duyệt các mục A | `docs/spec/01-softmax-theory.md`, bản web https://claude.ai/artifact/ScwHoNtA1WWJKCqLboefGu |

Chưa có gì trong `rtl/avalon/`, `ip/`, `sw/`: wrapper và hệ thống thuộc nhóm implement, không tự viết (`CLAUDE.md`).

## Đang chờ Chau

Đừng tự quyết các mục này. Chi tiết và đề xuất: `docs/spec/07-open-decisions.md` phần A. Chau đọc `docs/spec/01-softmax-theory.md` trước rồi mới duyệt; mục 14 của file đó nối từng mục A với phần toán liên quan.

| Mục | Cần gì | Việc phải làm sau khi có trả lời |
|---|---|---|
| A1 | Duyệt `03-design-spec.md` và 9 tài liệu block, trừ `smx_exp2` đã `APPROVED` | Chỉ khi Chau xác nhận mới đổi sang `APPROVED`, rồi cập nhật tracker |
| A4 | Có ghi lưu ý span 0x8000 không | Thêm vào `08-integration-notes.md` |
| A5 | Giữ `tag_q` trong M10K không; đề xuất giữ | Nếu đổi: sửa RTL, chạy lại regress và Fitter |
| A6 | Có ghi lưu ý LEN, ROWS vượt trường không báo ERR không | Thêm vào `08-integration-notes.md` |
| A7 | Có ghi yêu cầu ràng buộc timing `acc_*` không | Thêm vào `08-integration-notes.md` |

Câu hỏi khác đang chờ Chau:

- **Reset trên board:** A2 đã chốt là deassert do test drive, lõi không có bộ đồng bộ. `08-integration-notes.md` đang tạm ghi trên hệ thống thật là trách nhiệm của bên lái `rst_n`; chưa xác nhận.
- **Độ chi tiết sơ đồ:** có khối nào cần vẽ chi tiết hơn không. Ứng viên là `smx_csr`, đang gom khối thanh ghi và cổng X_BUF. Mặc định giữ nguyên.
- **Worktree cũ:** có xoá 9 worktree đã merge trong `.claude/worktrees` (98 MB) không. Chưa xoá.
- **PR vào `main`:** chỉ mở khi Chau yêu cầu.
- **Tài liệu trên claude.ai:** nhắc Chau tải lại docs lên Project; repo không tự đồng bộ.
- **Đề tài và lịch:** tên đề tài trong sheet nhóm 6, ngày nộp chính xác (`PROJECT.md` mục 9).
- **Đánh giá DeiT-Tiny:** tập dữ liệu, cách hiệu chuẩn S, layer chạy trên board (`02-target-workload.md` mục 8).

## Đang chờ nhóm khác

- **Nhóm implement:** `smx_avalon`, `ip/smx_hw.tcl`, hệ thống Platform Designer, script System Console, đo băng thông JTAG. Câu hỏi còn mở: họ dùng JTAG to Avalon Master Bridge không.
- **Nhóm verify (tiendangphuoc):** dùng ModelSim Intel FPGA Edition 10.5b gọi từ WSL (`source sim/setup.sh`), không UVM. Môi trường ở `tb/dv/`, 6 test và checker REQ-VER-03; chi tiết ở `tb/dv/README.md`, chạy cả bộ bằng `make dv`, xem sóng bằng `make dvview`. `make dv` PASS trên ModelSim ở P = 4/8/16 và N_SEG = 4/8/16 (2026-11-12), test ngẫu nhiên thêm SEED = 2, 3; bắt 12/12 lỗi cài thử dưới Verilator. Chưa tìm thấy lỗi RTL. Báo cáo: chương 6 đã có kết quả, log ModelSim của từng test (`docs/report/logs/`) và 7 ảnh dạng sóng chụp từ ModelSim (`docs/figures/dv_*_modelsim.png`, mở bằng `make dvview`); các hình `dv_*.pdf` vẽ từ VCD của Verilator bằng `docs/report/tools/dv_waves.py` không còn dùng trong báo cáo. Trang bìa đã có tên trường, ba thành viên và giảng viên; còn thiếu file logo `docs/figures/logo_bk.png`. các chương 1, 4, 5, 7, 8 đã cập nhật theo hiện trạng, cần Chau đọc lại. **Đang dở, tạm dừng 2026-11-12:** test mức bus Avalon. Bộ kiểm mức bus `smx_avalon_chk.sv` đã viết thử rồi gỡ khỏi cây (còn trong lịch sử git, commit `bbe538e`). Hai file `rtl/avalon/smx_avalon.sv` và `ip/smx_hw.tcl` của Curtis từng được chép về rồi gỡ ra theo yêu cầu của tiendangphuoc; chúng chỉ có trên nhánh `quartus/de10-project` (PR #1 chưa merge), nên test Avalon phải chờ PR đó vào `main` hoặc được cho phép lấy lại. Việc còn lại: thêm tham số `AVALON` cho `smx_dv_env` (wrapper làm DUT, `dut` làm lõi tham chiếu chạy song song), test `tb_smx_dv_avalon` (đọc liên tiếp theo latency 2, kiểm `smx_hw.tcl` theo REQ-IF-11), `make dv AVALON=1`. `make dv` và `make dvview` đã chạy được trên ModelSim sau khi thêm `+VCD` (2026-11-12). Ngày 2026-11-12, theo yêu cầu của tiendangphuoc, toàn bộ phần DV và báo cáo trên nhánh `claude/trusting-allen-95ekbo` được fast-forward thẳng vào `main`, không qua pull request. Trong đó có sửa `sim/Makefile` dùng chung (`make dv`, `make dvview`, `SEED`, `VCD`, xử lý `modelsim.ini` khi gọi từ WSL): Chau cần xem lại.

## Việc tiếp theo

Theo thứ tự, khi Chau không chỉ định khác. Lịch ở `PROJECT.md` mục 8.

1. Áp dụng các trả lời ở bảng trên, cập nhật `07-open-decisions.md` và `08-integration-notes.md`.
2. Rà sâu `smx_scale`, `smx_exp2`, `smx_norm` và đối chiếu tài liệu từng block với RTL. Phần này chưa làm xong: báo cáo của reviewer độc lập bị mất; port và hướng đã so bằng script, độ rộng thì chưa.
3. Quét số đo cho báo cáo: thêm seed ở P = 4, chạy Fitter ở N_SEG = 4 và 16, ghi số vào `smx_core.md`.
4. Đánh giá DeiT-Tiny bằng golden model: E1, E2 (`02-target-workload.md` mục 5), sau khi có trả lời ở trên.
5. Hỗ trợ nhóm implement chạy trên board và E3 khi họ sẵn sàng.
6. Báo cáo và demo, hạn khoảng 2026-12-21.

## Lưu ý vận hành

- **Git:** commit và push sau mỗi bước đã kiểm chứng, trên nhánh làm việc; không push thẳng `main`.
- **Tác vụ tự chạy tiếp:** "Resume softmax core work after quota" đang **tắt**, và gắn với phiên cũ `session_018kvwhthqKq5fC6j8brjM6B`. Phiên mới cần cơ chế này thì tạo tác vụ mới. Nó chỉ chạy khi máy bật và phiên còn sống.
- **`/tmp` mất khi tắt máy:** bench riêng của reviewer và script dựng ba trang artifact đều nằm ở đó, không có trong repo. Đừng tìm lại. Muốn sửa trang: dùng `Artifact` `action: read` với URL ở trên, sửa, rồi publish lại vào cùng URL để giữ link. Hai trang lớn nhúng SVG inline từ `docs/spec/fig/`; trang lý thuyết còn có công thức KaTeX render sẵn và font nhúng, lấy `katex`, `marked` từ `node_modules` của `@mermaid-js/mermaid-cli` trong `~/.local/lib/node_modules`.
- **Harness trên git:** từ 2026-11-06 `CLAUDE.md` và `.claude/commands/` nằm trên git để người nhận bàn giao dùng chung (có mục "Vai trò"). Chỉ `.claude/settings.json` (quyền cục bộ) và `.claude/worktrees/` bị ignore.
- **Vẽ sơ đồ:** theo `docs/spec/09-diagram-rules.md`. Không dùng Mermaid `flowchart` hay `stateDiagram`. Sau khi sinh hình, phải mở ảnh ra xem, vì script chỉ kiểm được phần quy tắc hình học.
- **Xem hình trên máy này:** không có browser cho `mmdc` và Playwright, nhưng có Firefox. Bọc SVG vào một file HTML trong scratch rồi chạy `firefox --headless --no-remote --profile <thư mục tạm> --window-size W,H --screenshot <scratch>/x.png file:///<scratch>/x.html`. Ghi ảnh ra scratch, vì repo chặn đọc file PNG.
- **Các trang artifact là bản chụp:** khi spec hoặc hình đổi đáng kể thì publish lại.

## Kiểm tra nhanh đầu phiên

```bash
git status -sb && git log --oneline -5
cd sim && make testname=tb_smx_core P=8 N_SEG=8      # khoảng 30 s, phải có TB_RESULT: PASS
```
