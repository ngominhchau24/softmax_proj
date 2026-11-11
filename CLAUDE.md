# CLAUDE.md — smx: Integer-Only Softmax Accelerator (BTL, DE10-Standard)

Đây là hướng dẫn cho Claude Code trong repo này.

## Đọc trước, theo thứ tự

1. `docs/PROGRESS.md` — đang ở đâu, chờ gì, làm gì tiếp. **Đọc đầu mỗi phiên; cập nhật trong cùng commit khi trạng thái đổi.**
2. `docs/KNOWLEDGE.md` — bản nén: thuật toán, tham số, thanh ghi, quy tắc cứng, trạng thái block. **Đủ cho phần lớn công việc; đọc file này trước mọi việc.**
3. `docs/PROJECT.md` và `docs/requirements.md` — chỉ mở khi cần quyết định gốc (D-mã), bảng nguồn số liệu, hoặc REQ-* chi tiết. Không đọc toàn bộ mỗi phiên.
4. `model/softmax_ref.py` — **nguồn chân lý về số học**; mở khi viết RTL hoặc sinh vector.
5. `docs/research/softmax-survey.md` — chỉ khi cần lý do của một lựa chọn kiến trúc.

`docs/archive/` là tài liệu đã huỷ (đề xuất GEMM). Không dùng làm định hướng.

## Project là gì (một đoạn)

IP Avalon-MM slave trên Cyclone V (DE10-Standard) tính softmax theo hàng cho điểm attention INT8, ra UINT8. Demo trên board qua JTAG + System Console, không cần Linux. Thuật ngữ: *golden model* = `model/softmax_ref.py`; *GHRD* = thiết kế mẫu Terasic. Số mũ cơ số 2 qua `u = q·K` (K = S·log₂e do HPS tính), IntMax + online normalization (2 lượt), 2^F bằng PWL, một phép chia mỗi hàng, P lane song song. Phạm vi của người dùng (Chau) là **thiết kế RTL**; verification và tích hợp board do thành viên khác làm.

## Vai trò: xác định trước khi làm

Hỏi người dùng đang giữ vai nào nếu chưa rõ. Các mục "không tự viết" bên dưới gắn với vai người thiết kế RTL.

- **Người thiết kế RTL (Chau):** làm `smx_core` và tài liệu block, theo mục "Ưu tiên hiện tại" và "Quy trình thiết kế".
- **Người nhận bàn giao (báo cáo, DV, board):** lõi RTL đã xong (xem `docs/PROGRESS.md`). Được viết phần của mình: `rtl/avalon/`, `ip/`, `sw/`, `tb/` và assertion cho verify, `docs/report/`. Không tự sửa RTL lõi, số học (`model/softmax_ref.py`), bản đồ thanh ghi hay requirements v1.0; phát hiện lỗi hoặc tài liệu sai thì ghi lại, báo người thiết kế RTL. Điểm vào cho từng mảng: `README.md`.

## Ưu tiên hiện tại: LÕI TRƯỚC

- Việc của Chau (và của Claude Code trong repo này) là **`smx_core`**: CSR, X_BUF, Y_BUF, controller, datapath, lộ cổng `acc_*` (REQ-IF-06) và conduit trạng thái. Kiến trúc: `docs/spec/04-architecture.md`.
- (Vai người thiết kế RTL) **Không** tự viết `rtl/avalon/smx_avalon.sv`, `ip/smx_hw.tcl`, hệ thống Platform Designer hay script System Console — đó là phần nhóm implement làm tiếp. Chỉ cập nhật `docs/spec/08-integration-notes.md` khi giao diện lõi thay đổi, hoặc khi người dùng yêu cầu rõ.
- Mọi kiểm thử lõi đi qua cổng `acc_*` trong testbench, không cần bus Avalon.
- Thứ tự block và trạng thái: `docs/spec/blocks/README.md` (exp2 → scale → maxtree → sumacc → divider → norm → buf → csr → ctrl → core), sau đó tổng hợp riêng lõi trong `syn/`.

## Quy trình thiết kế (bắt buộc, có cổng duyệt)

1. **Research** — đã xong cho kiến trúc (`docs/research/`). Research thêm khi một block cần (ghi file mới trong `docs/research/`, nguồn gắn nhãn).
2. **Architecture** — đã chốt v1.0 (`docs/spec/04-architecture.md`).
3. **Block design doc** — mỗi block một file `docs/spec/blocks/<block>.md` theo `_TEMPLATE.md`: chức năng, tham số, bảng port, số học bit-exact đối chiếu golden model, sơ đồ mermaid cấu trúc bên trong, timing + WaveDrom, tài nguyên ước tính, kế hoạch test, câu hỏi mở. Dùng lệnh `/block-doc <block>`. Trạng thái `DRAFT`.
4. **Cổng duyệt** — người dùng đọc và duyệt; chỉ người dùng được đổi sang `APPROVED` (hoặc bảo Claude đổi). Câu hỏi mở phải được trả lời trước.
5. **RTL + unit test** — chỉ khi block `APPROVED`. Dùng lệnh `/block-rtl <block>`. Testbench tự kiểm bit-exact với vector sinh từ golden model.
6. **Tích hợp** `smx_core`, test qua cổng `acc_*` với vector ngẫu nhiên + corner từ REQ-VER-02.
7. **Tổng hợp** lõi trong `syn/`: tài nguyên, Fmax ≥ 100 MHz; cập nhật số [TK] trong tài liệu bằng số thật.

Nếu khi viết RTL phát hiện tài liệu sai hoặc thiếu: dừng, sửa tài liệu, xin duyệt lại — không để RTL và tài liệu lệch nhau.

## Quy tắc không được vi phạm

1. **Số học**: RTL phải khớp `model/softmax_ref.py` bit-exact. Muốn đổi số học → đổi model trước, cập nhật `docs/requirements.md` mục 4, ghi Nhật ký trong `docs/PROJECT.md`, rồi mới sửa RTL. Không "tối ưu" làm lệch thứ tự nhóm, phép dịch cắt bỏ, hay làm tròn.
2. **Phạm vi đề tài**: không thêm GEMM, convolution, hay biến đề tài thành "activation accelerator" (trùng nhóm khác, xem PROJECT.md mục 4). Sigmoid/GELU chỉ là mở rộng tuỳ chọn khi lõi đã xong và người dùng yêu cầu.
3. **Giao diện**: bản đồ thanh ghi và bố trí buffer trong requirements mục 5 là hợp đồng với hai nhóm khác. Không đổi khi chưa được người dùng đồng ý; khi đổi phải tăng VERSION trong `HW_PARAM` và ghi Nhật ký.
4. **Không bịa số liệu**: tài nguyên, Fmax, latency phải đến từ báo cáo Quartus/mô phỏng thật. Thông số chip nếu không chắc thì ghi "cần đối chiếu".
5. **Requirements v1.0 đã đóng băng** (B1–B7, A1–A5 chốt 2026-10-31). Muốn đổi phải hỏi người dùng, ghi Nhật ký, cập nhật bảng nguồn PROJECT.md mục 7.1. Mọi số liệu mới đưa vào tài liệu phải ghi loại nguồn ([TL]/[GM]/[TK]/[ĐC]).

## Quy ước SystemVerilog (Quartus Prime Lite 18.1)

- Dùng: `logic`, `always_ff`, `always_comb`, `package` + `import`, `parameter`/`localparam`, `typedef enum logic [..]`, mảng packed/unpacked, `generate`, `$clog2`.
- Tránh trong file tổng hợp: `interface`/`modport` ở port, `struct` ở port top-level, class, SVA, `initial` (trừ `$readmemh` cho ROM), `$display`, `unique/priority case` lồng phức tạp, gán `'{default:...}` cho mảng unpacked ở port.
- Một clock `clk`, reset `rst_n` active-low bất đồng bộ (`always_ff @(posedge clk or negedge rst_n)`).
- Phép nhân viết `a * b` với toán hạng `signed` khi cần, để Quartus map vào DSP. Đăng ký (register) đầu vào/đầu ra của bộ nhân để đạt 100 MHz.
- RAM: inferred theo template Intel (simple dual-port, registered output); nếu không ra M10K thì dùng `altsyncram`.
- Tên module tiền tố `smx_`; file trùng tên module; một module mỗi file. Tên tín hiệu, comment: tiếng Anh. Hậu tố `_q` cho thanh ghi, `_d` cho next-state khi tách.
- Tham số chung ở `rtl/pkg/smx_pkg.sv`. Bảng PWL sinh bằng `python3 model/softmax_ref.py --gen-pwl N` hoặc `--gen-hex N path`, không sửa tay.
- SVA cho nhóm verify đặt trong `tb/` hoặc file `*_bind.sv` riêng.

## Bố cục repo

```
CLAUDE.md               file này
docs/PROJECT.md         nền tảng + quyết định + nhật ký
docs/requirements.md    REQ-*, số học, thanh ghi
docs/research/          khảo sát tài liệu
docs/spec/              04-architecture.md (top), 08-integration-notes.md (bàn giao nhóm implement)
docs/spec/blocks/       <block>.md theo _TEMPLATE.md + README.md (bảng trạng thái)
docs/spec/wave/         WaveDrom JSON
.claude/commands/       /block-doc, /block-rtl
docs/archive/           tài liệu đã huỷ
model/softmax_ref.py    golden model + sinh bảng PWL + sinh vector
rtl/pkg/                smx_pkg.sv, pwl_n*.hex
rtl/core/               smx_core và khối con
rtl/avalon/             smx_avalon (wrapper mỏng — nhóm implement)
tb/                     unit testbench tự kiểm; tb/vectors/ sinh từ golden model
sim/                    Makefile để mô phỏng, chạy từ thư mục này
scripts/                compile.f (= rtl.f + tb.f + testcase.f), setup.sh (trỏ flow tới ModelSim)
ip/                     smx_hw.tcl (nhóm implement)
syn/                    Quartus project chỉ cho IP
sw/                     mã HPS tham khảo
```

## Lệnh thường dùng

```bash
python3 model/softmax_ref.py --selftest          # kiểm model + đo sai số
python3 model/softmax_ref.py --gen-pwl 8         # in localparam bảng PWL
python3 model/softmax_ref.py --gen-hex 8 rtl/pkg/pwl_n8.hex
# Mô phỏng (ModelSim/Questa): một flow duy nhất ở sim/, chi tiết ở docs/KNOWLEDGE.md mục 7, lệnh /sim.
# Không viết script chạy riêng; block mới thì thêm vào scripts/rtl.f và scripts/testcase.f:
cd sim && make testname=tb_smx_exp2 N_SEG=8      # clean + compile + run, fail thì make trả lỗi
cd sim && make regress                           # compile, chạy N_SEG = 4 8 16
cd sim && make run WAVE=1                        # chạy lại không compile, ghi wave/<run>.wlf
# Tổng hợp (khi có syn/smx.qpf):
#   quartus_sh --flow compile syn/smx
```

## Cách làm việc với người dùng

- Trao đổi bằng **tiếng Việt**, văn xuôi có lập luận liền mạch; code và comment bằng tiếng Anh.
- Người dùng là kỹ sư DV (SystemVerilog/UVM/Questa) — giải thích ở mức kỹ sư, không cần dạy cơ bản HDL.
- Sơ đồ khối, datapath, FSM: kiểu sơ đồ vi mạch, dây thẳng bẻ góc vuông, không đường cong, theo `docs/spec/09-diagram-rules.md`; vẽ bằng script trong `docs/spec/fig/`, không dùng Mermaid `flowchart` hay `stateDiagram` cho hình mới. Sequence vẫn dùng Mermaid; dạng sóng/timing chu kỳ bằng WaveDrom JSON trong `docs/spec/wave/`. Tất cả đều phải sửa tay được.
- Trước khi viết một khối RTL mới: nêu ngắn giao diện (port, latency, handshake) và cách kiểm nó với golden model.
- Mỗi khối có testbench sanity tự kiểm bằng vector sinh từ `model/softmax_ref.py` trước khi tích hợp.
- Sau khi chốt hoặc đổi một quyết định: cập nhật `docs/PROJECT.md` (mục 7 + 10). Kết quả research mới: thêm file vào `docs/research/`.
- Repo này không đồng bộ tự động với claude.ai Project; khi docs thay đổi đáng kể, nhắc người dùng tải lại lên Project.
