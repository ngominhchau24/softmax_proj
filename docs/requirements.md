# Requirements — `smx`: Integer-Only Softmax Accelerator (v1.0)

> Trạng thái: **v1.0 — đã duyệt 2026-10-31, giao diện đóng băng** (HW_PARAM VERSION = 0x10). Nguồn của từng giá trị: `docs/PROJECT.md` mục 7.1. Mọi thay đổi phải ghi vào `docs/PROJECT.md` mục Nhật ký và cập nhật `model/softmax_ref.py` nếu chạm tới số học.
>
> Nguồn chân lý về số học: **`model/softmax_ref.py`**. Mục 4 dưới đây mô tả cùng thuật toán bằng lời; khi có mâu thuẫn, coi đó là bug tài liệu và sửa cả hai.

Quy ước mã yêu cầu: `REQ-<nhóm>-<số>`. Nhóm: `FUN` chức năng, `ARI` số học, `IF` giao diện, `PRF` hiệu năng, `RES` tài nguyên, `IMP` hiện thực, `VER` hỗ trợ verification.

---

## 1. Phạm vi

Accelerator tính softmax theo hàng cho ma trận điểm attention đã lượng tử hoá INT8, trả về xác suất UINT8. Một lần chạy xử lý R hàng, mỗi hàng L phần tử. Không có masking, requantization đầu vào, hay các phép khác của Transformer (GEMM, LayerNorm, GELU) — chúng thuộc nhóm khác hoặc ngoài phạm vi.

## 2. Tham số tổng hợp

| Tham số | Giá trị | Ý nghĩa |
|---|---|---|
| `P` | 8 | Số lane song song (phần tử xử lý mỗi chu kỳ) |
| `L_MAX` | 512 | Độ dài hàng tối đa (lũy thừa của 2) |
| `R_MAX` | 16 | Số hàng tối đa mỗi lần chạy |
| `N_SEG` | 8 | Số đoạn PWL của 2^F (4/8/16, tham số hoá) |
| `K_FRAC` | 16 | Số bit lẻ của hệ số K |

Các tham số phải đọc được qua thanh ghi `HW_PARAM`.

## 3. Yêu cầu chức năng

- **REQ-FUN-01** Với mỗi hàng r ∈ [0, R), accelerator tính `Y[r][i] = softmax_q(X[r][0..L−1])[i]` cho mọi i ∈ [0, L), theo đúng thuật toán mục 4.
- **REQ-FUN-02** L và R lập trình qua thanh ghi, `1 ≤ L ≤ L_MAX`, `1 ≤ R ≤ R_MAX`. L không cần là bội của P.
- **REQ-FUN-03** Phần tử của X_BUF/Y_BUF ở vị trí i ≥ L của mỗi hàng không ảnh hưởng tới kết quả; nội dung Y_BUF tại i ≥ L là không xác định.
- **REQ-FUN-04** Nếu `START` được ghi khi L hoặc R ngoài khoảng hợp lệ, accelerator không chạy, đặt `DONE = 1` và `ERR = 1`.
- **REQ-FUN-05** Kết quả chỉ phụ thuộc vào X, L, K (và tham số tổng hợp); không phụ thuộc vào lần chạy trước (không trạng thái giữa các lần chạy, ngoài CSR).

## 4. Đặc tả số học (bit-exact)

Ký hiệu: `>>` là dịch phải số học (floor), mọi đại lượng là số nguyên.

- **REQ-ARI-01 Đầu vào.** `q` là INT8 có dấu (two's complement). Giá trị thực `x = S·q`, S là scale lượng tử hoá của điểm attention (đã gồm 1/√d nếu có).
- **REQ-ARI-02 Hệ số K.** `K = round(S·log₂e·2¹⁶)`, số nguyên không dấu 16 bit (UQ0.16), do phần mềm HPS tính và ghi vào `SCALE_K`. Ràng buộc: `0 < S < ~0,693` (để K vừa 16 bit). Phần cứng không tính log; không có hằng log nào khác trong datapath.
- **REQ-ARI-03 Số mũ cơ số 2.** `u_k = q_k · K` (có dấu, 25 bit, Q8.16). `c_k = ⌈u_k / 2¹⁶⌉` (có dấu, 9 bit).
- **REQ-ARI-04 Hàm E(d)**, với `d ≤ 0` biểu diễn `d/2¹⁶`:
  `I = d >> 16`, `F = d & 0xFFFF`, `idx = F >> (16 − log₂N_SEG)`, `r = F & (2^(16−log₂N_SEG) − 1)`,
  `E₀ = C[idx] + ((M_[idx] · r) >> (16 − log₂N_SEG))` (UQ1.15, 16 bit),
  `E = 0` nếu `−I > 15`, ngược lại `E = E₀ >> (−I)`.
  Bảng `C[i] = round(2^(i/N)·2¹⁵)`, `M_[i] = round((2^((i+1)/N) − 2^(i/N))·2¹⁵)`, sinh bằng `model/softmax_ref.py --gen-pwl N`.
- **REQ-ARI-05 Lượt 1 (online normalization với IntMax).** Duyệt nhóm g = 0, 1, … gồm các chỉ số `[gP, min(gP+P, L))` theo thứ tự tăng:
  `Mg = max c_k` trong nhóm; `Mnew = Mg` với nhóm đầu, ngược lại `max(M, Mg)`;
  `sum = (sum >> (Mnew − M)) + Σ_nhóm E(u_k − Mnew·2¹⁶)`; `M = Mnew`.
  `sum` không dấu, ≥ 25 bit (≤ 512·2¹⁶). Thứ tự nhóm và phép dịch cắt bỏ là một phần của đặc tả (ảnh hưởng bit-exact).
- **REQ-ARI-06 Nghịch đảo.** `Rcp = ⌊2⁴⁰ / sum⌋` (27 bit; vì `sum ≥ 2¹⁴` khi kết thúc lượt 1).
- **REQ-ARI-07 Lượt 2.** Với mỗi k < L: `e = E(u_k − M·2¹⁶)` (M là giá trị cuối lượt 1, tính lại từ X_BUF), `y = min(255, (e·Rcp + 2³¹) >> 32)`. Đầu ra UINT8, giá trị thực `y/256`.
- **REQ-ARI-08 Bão hoà.** Xác suất 1,0 không biểu diễn được; bão hoà về 255. Không có trường hợp tràn nào khác (đã chứng minh bằng độ rộng ở trên).

Độ chính xác đo bằng model (hàng ngẫu nhiên L = 128, S ∈ {0,02; 0,0625; 0,2}): sai số tuyệt đối tối đa so với softmax float64 ≈ 0,00195–0,0020 với N_SEG = 8, tức bằng nửa LSB đầu ra — sai số bị chi phối bởi lượng tử hoá UINT8, không phải bởi xấp xỉ hàm mũ.

## 5. Giao diện

### 5.1. Bus và hệ thống

- **REQ-IF-01** IP là một Avalon-MM slave, data 32 bit, địa chỉ theo word, không burst. Phải cắm được nguyên trạng vào hai kiểu hệ thống Platform Designer: (a) **đường demo chính**: hệ thống không HPS, master là JTAG to Avalon Master Bridge, điều khiển từ PC bằng System Console; (b) **tuỳ chọn**: GHRD Terasic DE10-Standard, master là lightweight HPS-to-FPGA bridge (bản chất AXI, Platform Designer tự chèn bộ chuyển AXI→Avalon và burst adapter).
- **REQ-IF-02** Read latency cố định 2 chu kỳ, không dùng `waitrequest`. Khai báo trong `ip/smx_hw.tcl`.
- **REQ-IF-03** Hỗ trợ `byteenable` 4 bit khi ghi X_BUF và các thanh ghi R/W (ghi byte/halfword đúng ngữ nghĩa); đọc luôn trả nguyên word. Lý do: tránh lỗi âm thầm khi phần mềm truy cập bằng con trỏ 8/16 bit.
- **REQ-IF-04** Một miền clock duy nhất từ Platform Designer. Reset `rst_n` active-low, assert bất đồng bộ, deassert đồng bộ.
- **REQ-IF-05** Báo hoàn thành bằng polling bit `DONE`; không có IRQ.
- **REQ-IF-06** Ranh giới bàn giao: `smx_core` chứa **toàn bộ** CSR, X_BUF, Y_BUF, controller và datapath, và lộ ra một cổng truy cập bộ nhớ đơn giản (`acc_addr` word 13 bit, `acc_write`, `acc_writedata[31:0]`, `acc_byteenable[3:0]`, `acc_read`, `acc_readdata[31:0]`, read latency cố định 2, không stall) cùng `clk`, `rst_n` và conduit trạng thái. Wrapper `smx_avalon` chỉ đổi tên tín hiệu sang Avalon; `smx_hw.tcl` và hệ thống Platform Designer thuộc nhóm implement (xem `docs/spec/integration-notes.md`). Verify lõi qua cổng `acc_*` mà không cần bus.
- **REQ-IF-10** Conduit trạng thái `status_busy`, `status_done`, `status_err` (đồng bộ, active-high) xuất ra ngoài component để có thể nối LED khi demo; để trống không ảnh hưởng chức năng.
- **REQ-IF-11** `smx_hw.tcl` khai báo: interface `clock`, `reset` (reset_n, associated clock), avalon slave `s0` với `addressUnits WORDS`, `readLatency 2`, không `waitrequest`, không burst, `byteenable` 4 bit; conduit `status`.

Ghi chú thuật ngữ: trong project, **golden model** = `model/softmax_ref.py`; **GHRD** = Golden Hardware Reference Design của Terasic. Không dùng lẫn.

### 5.2. Bản đồ thanh ghi (offset byte, span 0x6000)

| Offset | Tên | Truy cập | Bit | Mô tả |
|---|---|---|---|---|
| 0x0000 | CTRL | W | [0] START | Ghi 1 để chạy (tự xoá). Các bit khác bỏ qua. |
| 0x0004 | STATUS | R | [0] BUSY, [1] DONE, [2] ERR | DONE, ERR sticky; xoá khi có START mới. |
| 0x0008 | LEN | R/W | [9:0] | L, 1..L_MAX |
| 0x000C | ROWS | R/W | [4:0] | R, 1..R_MAX |
| 0x0010 | SCALE_K | R/W | [15:0] | K (UQ0.16) |
| 0x0014 | CYCLE_CNT | R | [31:0] | Số chu kỳ từ START tới DONE của lần chạy gần nhất |
| 0x0018 | HW_PARAM | R | [7:0] P, [11:8] log₂L_MAX, [19:12] R_MAX, [23:20] log₂N_SEG, [31:24] VERSION | |
| 0x2000–0x3FFF | X_BUF | R/W | | INT8, hàng r phần tử i tại byte `r·L_MAX + i` |
| 0x4000–0x5FFF | Y_BUF | R | | UINT8, cùng bố trí X_BUF |

- **REQ-IF-07** Đóng gói 4 phần tử 8 bit/word, little-endian: byte 0 (bit [7:0]) là phần tử chỉ số nhỏ nhất.
- **REQ-IF-08** Đọc thanh ghi chưa định nghĩa trả 0; ghi bị bỏ qua.
- **REQ-IF-09** Truy cập X_BUF/Y_BUF/LEN/ROWS/SCALE_K khi `BUSY = 1` là **không xác định**; chỉ STATUS và CYCLE_CNT được đọc an toàn khi đang chạy.

### 5.3. Trình tự phần mềm (System Console Tcl hoặc HPS)

Địa chỉ dưới đây là offset so với base của IP: qua JTAG master là base do Platform Designer gán; qua HPS là `0xFF200000 + base` (cần đối chiếu tài liệu Terasic).

1. Tính `K = round(S·log₂e·65536)`, ghi `SCALE_K`.
2. Ghi R hàng vào X_BUF (stride L_MAX byte), ghi `LEN`, `ROWS`.
3. Ghi `CTRL.START = 1`.
4. Poll `STATUS` tới khi `DONE = 1`; nếu `ERR = 1` thì cấu hình sai.
5. Đọc Y_BUF; đọc `CYCLE_CNT` nếu cần đo.

## 6. Hiệu năng

- **REQ-PRF-01** Tần số mục tiêu của IP ≥ **100 MHz** trên Cyclone V 5CSXFC6D6F31C6 (timing slack dương trong báo cáo TimeQuest với constraint 100 MHz). Board chạy ở clock GHRD cấp.
- **REQ-PRF-02** Throughput mỗi lượt: P phần tử/chu kỳ khi pipeline đầy.
- **REQ-PRF-03** Latency mỗi hàng ≤ `2·⌈L/P⌉ + 64` chu kỳ (bao gồm bộ chia ~27–32 chu kỳ và độ sâu pipeline). L = 512, P = 8 → ≤ 192 chu kỳ/hàng.
- **REQ-PRF-04** Chồng lặp bộ chia hàng r với lượt 1 hàng r+1 là **tuỳ chọn**, không bắt buộc ở v1.0.

## 7. Tài nguyên

- **REQ-RES-01** Sau Fitter Quartus 18.1: tổng ALUT + DSP block > 1000 (yêu cầu môn học). Kỳ vọng: vài nghìn ALUT, 12–24 DSP, X_BUF/Y_BUF trong M10K.
- **REQ-RES-02** Báo cáo tài nguyên của riêng IP (project `syn/` không gồm HPS) và của toàn hệ thống GHRD.

## 8. Hiện thực

- **REQ-IMP-01** Lõi (exp unit, reduction, divider, controller, datapath) tự viết bằng SystemVerilog; RAM có thể infer hoặc `altsyncram`.
- **REQ-IMP-02** Chỉ dùng tập con SystemVerilog Quartus 18.1 tổng hợp ổn định (xem `CLAUDE.md`).
- **REQ-IMP-03** Bảng PWL sinh từ `model/softmax_ref.py`, không sửa tay.
- **REQ-IMP-04** Không có assertion/`initial`/`$display` trong file tổng hợp, trừ `initial $readmemh` cho ROM nếu cần.

## 9. Hỗ trợ verification (bàn giao cho nhóm verify)

- **REQ-VER-01** Golden model `model/softmax_ref.py` (hàm `softmax_row`) dùng làm scoreboard; RTL phải khớp bit-exact trên mọi hàng.
- **REQ-VER-02** Danh sách kịch bản tối thiểu: L = 1, L = P, L = P±1, L = L_MAX; R = 1 và R_MAX; K = 0, K = 1, K = 65535; hàng toàn −128, toàn 127, đồng nhất, one-hot cực trị; hàng có max xuất hiện ở nhóm cuối (kiểm phép dịch hiệu chỉnh); ngẫu nhiên.
- **REQ-VER-03** Assertion đề xuất (file bind riêng): START khi BUSY bị bỏ qua; DONE chỉ lên sau khi BUSY xuống; LEN/ROWS ngoài khoảng → ERR; không có X/Z trên đường đọc Avalon khi `readdatavalid`.
- **REQ-VER-04** `CYCLE_CNT` phải khớp công thức latency trong micro-arch spec (dùng làm kiểm tra hiệu năng).
