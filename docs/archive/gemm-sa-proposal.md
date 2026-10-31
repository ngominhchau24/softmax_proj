# [ARCHIVE] Đề xuất GEMM systolic (đã huỷ 2026-10-21)

> Huỷ vì trùng đề tài nhóm 2 và 5. Giữ lại để tham khảo: lập luận dataflow, quy ước Avalon/CSR, danh sách tài liệu nền accelerator. KHÔNG dùng làm định hướng thiết kế.

## 4. Đề tài đã chọn và cơ sở lựa chọn

> **[ĐÃ HUỶ 2026-10-21]** Đề tài GEMM INT8 systolic ở mục 4–5 trùng nhóm 2 và nhóm 5. Giữ nội dung dưới đây chỉ để tham khảo các phần còn dùng lại được (Avalon wrapper, CSR + polling DONE, quy ước RTL, tài liệu nền). Đề tài thay thế: `[CHƯA CHỐT]`, xem mục 10.

### 4.1. Đề tài

**`gemm_sa`: accelerator nhân ma trận số nguyên INT8 dùng systolic array 2D kiểu output-stationary, kích thước N×N tham số hóa (mặc định N = 8).** Mỗi lần chạy tính một tile đầu ra

```
C[N×N] (+)= A[N×K] × B[K×N],   1 ≤ K ≤ K_MAX (mặc định 256)
```

### 4.2. Lý do chọn (tóm tắt từ khảo sát tài liệu, mục 12)

- GEMM là kernel trung tâm của DNN: lớp fully-connected là GEMM trực tiếp, lớp convolution quy về GEMM qua im2col (Caffeine, Gemmini chạy im2col trên CPU và GEMM trên accelerator). Một kernel GEMM là "phép toán bên trong mạng AI" theo nghĩa chặt nhất.
- Systolic array là cấu trúc đã được kiểm chứng từ Kung (1982) đến TPU (2017) và Gemmini (2021): đều đặn, chỉ giao tiếp láng giềng, mỗi lần đọc bộ nhớ được tái sử dụng qua nhiều PE — rất hợp với FPGA và dễ phân tích throughput.
- INT8 nhân / INT32 cộng dồn là chuẩn suy luận lượng tử hóa (TPU, Jacob et al. 2018), ánh xạ gọn vào DSP Cyclone V.
- Output-stationary (OS) thay vì weight-stationary (WS): OS giữ tổng riêng trong PE nên không cần pha nạp trọng số và không cần đẩy tổng riêng qua mảng; vòng lặp K chạy tự nhiên ngay trong PE. Với một kernel đơn, buffer on-chip nhỏ, OS cho control đơn giản nhất. WS (kiểu TPU) chỉ có lợi rõ khi tái sử dụng trọng số qua nhiều batch, điều mà demo này không khai thác. Lựa chọn OS/WS được trình bày như một trade-off trong báo cáo, dẫn SCALE-Sim.
- Phương án bị loại: convolution engine 3×3 (line buffer làm tăng độ phức tạp mà không thêm giá trị cho demo chỉ-cần-chạy-đúng), row-stationary kiểu Eyeriss (gắn chặt với thiết kế PE riêng và NoC, quá nặng cho 2 tháng), MLP end-to-end (ngoài phạm vi demo đã chốt).

## 5. Kiến trúc `[ĐỀ XUẤT — sẽ đóng băng trong spec giao diện v1.0]`

### 5.1. Số học (mục B)

- A, B: **INT8 có dấu** (two's complement). C: **INT32 có dấu**.
- Tích 8×8 → 16 bit có dấu, cộng dồn vào accumulator 32 bit.
- **Không cần saturate:** với K ≤ 256, |tổng| ≤ 256 · 128 · 128 = 2²² ≪ 2³¹, nên không thể tràn trong một lần chạy. Khi dùng chế độ cộng dồn nhiều lần (`ACC_EN`), ngữ nghĩa là **wrap two's complement 32 bit**, trùng với `numpy.int32` để golden model khớp bit-exact.
- Không có requantization, bias hay activation.

### 5.2. Phân chia tiling HW/SW (mục C)

Phương án lai, tối ưu cho một kernel:

- **Phần cứng lo chiều K:** trong một lần chạy, mảng PE quét toàn bộ K (tối đa `K_MAX`) và cộng dồn tại chỗ — đây chính là thế mạnh của OS, đồng thời mỗi tile đầu ra chỉ phải đọc về đúng một lần.
- **Phần mềm HPS lo chiều M và N:** với ma trận lớn hơn N×N, HPS lặp qua các tile đầu ra, mỗi tile nạp lại phần A/B tương ứng và đọc C. Vòng lặp này đơn giản, nằm hoàn toàn ở phía nhóm implement.
- **K > K_MAX:** HPS chia K thành nhiều đoạn, chạy đoạn đầu với `ACC_EN = 0`, các đoạn sau với `ACC_EN = 1` (không xoá accumulator), chỉ đọc C sau đoạn cuối.
- Kích thước không chia hết cho N: HPS đệm zero; phần cứng không cần xử lý biên.
- Mở rộng tùy chọn nếu dư thời gian: bộ sinh địa chỉ cho phép phần cứng tự lặp nhiều tile M/N; double-buffering A/B để chồng nạp dữ liệu với tính toán.

### 5.3. Sơ đồ khối

```
            Avalon-MM slave (32-bit) ── nối vào lightweight HPS-to-FPGA bridge
                         │
                ┌────────┴─────────────────────────────────────────┐
                │ gemm_sa_avalon (wrapper do project này viết)     │
                │   address decode: CSR | A_BUF | B_BUF | C_BUF    │
                └───┬──────────┬───────────┬──────────────┬────────┘
                    │CSR       │wr A       │wr B          │rd C
                ┌───▼────┐ ┌───▼────┐ ┌────▼───┐     ┌────▼───┐
                │ ctrl   │ │ A_BUF  │ │ B_BUF  │     │ C_BUF  │
                │ FSM    │ │ M10K   │ │ M10K   │     │ M10K   │
                └───┬────┘ └───┬────┘ └────┬───┘     └────▲───┘
                    │          │ N×8b/cycle│ N×8b/cycle   │ drain
                    │      ┌───▼───────────▼────┐         │
                    └─────►│ skew regs (tam giác)│        │
                           │ N×N PE array (OS)  ├─────────┘
                           └────────────────────┘
```

- **PE:** nhận `a` từ trái, `b` từ trên; `acc <= acc + a*b`; chuyển `a` sang phải, `b` xuống dưới sau 1 chu kỳ. Tín hiệu `clr` xoá accumulator khi bắt đầu (nếu `ACC_EN = 0`).
- **Skew:** hàng i của A trễ i chu kỳ, cột j của B trễ j chu kỳ (thanh ghi dịch tam giác).
- **Drain:** sau khi luồng dữ liệu ra khỏi mảng, controller sao chép N×N accumulator sang C_BUF (dịch theo hàng, N chu kỳ, C_BUF chia N bank) — chi tiết chốt trong micro-arch spec.
- **Latency ước lượng:** ≈ K + 2(N−1) chu kỳ tính + N chu kỳ drain + vài chu kỳ điều khiển. Với N = 8, K = 256: ~280 chu kỳ cho 16 384 MAC, hiệu suất sử dụng PE ≈ 91%. Đỉnh 64 MAC/chu kỳ.

### 5.4. Bố trí dữ liệu trong buffer

- **A_BUF** lưu **theo cột của A** (tức A chuyển vị): entry k chứa `A[0..N−1][k]`, N byte. Mỗi chu kỳ đọc một entry để cấp cho cạnh trái mảng.
- **B_BUF** lưu **theo hàng của B**: entry k chứa `B[k][0..N−1]`, N byte.
- **C_BUF**: `C[i][j]` INT32, row-major.
- Đóng gói phía bus: 4 phần tử INT8 trên một word 32 bit, little-endian (byte 0 = phần tử chỉ số nhỏ nhất). Với N = 8, mỗi entry A/B = 2 word.

### 5.5. Hợp đồng giao diện với nhóm implement (mục D)

- **Bus:** một Avalon-MM slave duy nhất, data 32 bit, địa chỉ word, không burst, nối vào **lightweight HPS-to-FPGA bridge** của GHRD Terasic. Đóng gói kèm file `gemm_sa_hw.tcl` để thêm vào Platform Designer như component thường.
- **Read latency:** `[ĐỀ XUẤT]` cố định 2 chu kỳ (khai báo trong `_hw.tcl`), không dùng `waitrequest`.
- **Báo hoàn thành:** HPS **poll** bit `DONE`. Không dùng IRQ.
- **Clock:** một miền clock duy nhất do wrapper cấp (GHRD mặc định 50 MHz). Mục tiêu timing của RTL: **≥ 100 MHz** trên Cyclone V -C6 để có biên; chạy board ở tần số mà GHRD cấp.
- **Reset:** `rst_n` active-low, assert bất đồng bộ / deassert đồng bộ, lấy từ reset của Platform Designer.

**Bản đồ thanh ghi `[ĐỀ XUẤT]`** (offset byte so với base của component):

| Offset | Tên | Truy cập | Mô tả |
|--------|-----|----------|-------|
| 0x0000 | CTRL | W | bit0 `START` (ghi 1 để chạy, tự xoá); bit1 `ACC_EN` (1 = không xoá accumulator trước khi chạy) |
| 0x0004 | STATUS | R | bit0 `BUSY`; bit1 `DONE` (sticky, xoá khi có `START` mới) |
| 0x0008 | K_LEN | R/W | số bước K của lần chạy, 1..K_MAX |
| 0x000C | CYCLE_CNT | R | số chu kỳ từ `START` đến `DONE` của lần chạy gần nhất — dùng cho phân tích hiệu năng |
| 0x0010 | HW_PARAM | R | `[7:0]` = N, `[23:8]` = K_MAX, `[31:24]` = version |
| 0x1000–0x1FFF | A_BUF | W | entry k ở word `2k`, `2k+1` (với N = 8) |
| 0x2000–0x2FFF | B_BUF | W | như A_BUF |
| 0x3000–0x30FF | C_BUF | R | word `i·N + j` = `C[i][j]` |

Quy tắc: ghi buffer hoặc CSR (trừ đọc STATUS) khi `BUSY = 1` là **không xác định**; phần mềm phải chờ `DONE`. Ghi `K_LEN` ngoài khoảng 1..K_MAX là không xác định (nhóm verify nên có assertion cho điều này).

**Trình tự sử dụng phía HPS:** ghi A_BUF, B_BUF → ghi K_LEN → ghi CTRL (`START`, `ACC_EN`) → poll STATUS đến khi `DONE = 1` → đọc C_BUF (và CYCLE_CNT nếu cần đo).

## 6. Quy ước RTL (mục E)

- Lõi accelerator (PE, mảng, skew, controller) **tự viết toàn bộ**. Các thành phần hạ tầng được phép dùng IP: block RAM có thể infer hoặc dùng `altsyncram`, phần còn lại của hệ thống dùng IP Platform Designer/GHRD.
- `[ĐỀ XUẤT]` Buffer viết dạng **inferred RAM** theo template Intel (dễ mô phỏng, không phụ thuộc thư viện IP); nếu Quartus không suy ra M10K như mong muốn thì chuyển sang `altsyncram`.
- Phép nhân viết `a * b` với toán hạng `signed`, để Quartus tự ánh xạ vào DSP.
- Tách rõ **lõi thuần** (`gemm_sa_core`, giao diện đơn giản kiểu SRAM + CSR) và **wrapper Avalon** (`gemm_sa_avalon`) để nhóm verify kiểm thử lõi độc lập với bus.
- Ngôn ngữ: tên tín hiệu, module, comment trong code bằng tiếng Anh; trao đổi bằng tiếng Việt.
- Cấu trúc thư mục: `rtl/`, `rtl/pkg/`, `ip/` (`_hw.tcl`), `docs/` (spec), `syn/` (project Quartus chỉ để kiểm tra tổng hợp và timing của riêng IP).

## 7. Bàn giao cho nhóm verify và implement

- **Spec giao diện v1.0** (bản đồ thanh ghi, bố trí dữ liệu, trình tự, timing diagram Avalon) — giao **sớm nhất có thể** để hai nhóm bắt đầu song song.
- **Micro-architecture spec:** sơ đồ khối, FSM, pipeline/timing của mảng, công thức latency, danh sách tham số.
- **RTL** + file `_hw.tcl` + báo cáo tổng hợp của riêng IP (tài nguyên, Fmax).
- **Gợi ý verification:** danh sách điểm cần kiểm (giá trị biên INT8 −128/127, K = 1 và K = K_MAX, `ACC_EN`, ma trận zero/đơn vị, ngẫu nhiên), danh sách assertion đề xuất. Golden model Python/NumPy do nhóm verify viết, theo đúng ngữ nghĩa ở mục 5.1 và bố trí ở mục 5.4.
## 12. Tài liệu tham khảo (khảo sát ban đầu)

1. H. T. Kung, "Why Systolic Architectures?", *IEEE Computer*, 15(1), 1982, pp. 37–46. — Nguyên lý systolic: mỗi lần truy cập bộ nhớ phục vụ nhiều phép tính.
2. N. P. Jouppi et al., "In-Datacenter Performance Analysis of a Tensor Processing Unit", ISCA 2017. — Systolic array 256×256 MAC 8 bit, weight-stationary.
3. T. Chen et al., "DianNao: A Small-Footprint High-Throughput Accelerator for Ubiquitous Machine-Learning", ASPLOS 2014. — Nhấn mạnh vai trò của bộ nhớ trong thiết kế accelerator.
4. Y.-H. Chen, J. Emer, V. Sze, "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for CNNs", ISCA 2016. — Phân loại dataflow (OS/WS/IS/RS/NLR), đề xuất row-stationary.
5. V. Sze et al., "Efficient Processing of Deep Neural Networks: A Tutorial and Survey", *Proc. IEEE*, 105(12), 2017. — Khung lý thuyết và thước đo đánh giá cho báo cáo.
6. C. Zhang et al., "Optimizing FPGA-based Accelerator Design for Deep Convolutional Neural Networks", FPGA 2015. — Roofline model, loop tiling trên FPGA.
7. J. Qiu et al., "Going Deeper with Embedded FPGA Platform for Convolutional Neural Network", FPGA 2016. — Kiến trúc CPU + FPGA trên SoC nhúng, lượng tử hóa fixed-point.
8. B. Jacob et al., "Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference", CVPR 2018. — Cơ sở cho INT8 nhân / INT32 cộng dồn.
9. A. Samajdar et al., "SCALE-Sim: Systolic CNN Accelerator Simulator", arXiv:1811.02883, 2018 (và bản ISPASS 2020). — Mô hình hóa OS/WS/IS trên systolic array.
10. H. Genc et al., "Gemmini: Enabling Systematic Deep-Learning Architecture Evaluation via Full-Stack Integration", DAC 2021. — Generator systolic array hỗ trợ cả OS và WS; im2col trên CPU, GEMM trên accelerator.
