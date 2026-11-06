# Khảo sát tài liệu: Accelerator Softmax số nguyên cho Transformer

> Tài liệu research cho đề tài D12 (xem `claude/PROJECT.md`). Ngày khảo sát: 2026-10-31.
> Mục đích: (1) nắm các thuật toán softmax thân thiện phần cứng, (2) rút ra lựa chọn kiến trúc cho RTL trên Cyclone V (DE10-Standard), (3) liệt kê các quyết định cần chốt trước khi viết spec.
> Quy ước: "đề xuất" là kết luận của khảo sát này, chưa phải quyết định đã chốt.

---

## 1. Tóm tắt điều hành

Các công trình về softmax phần cứng giải quyết cùng ba nút thắt: **hàm mũ**, **phép chia**, và **lượt quét thêm để tìm max**. Lời giải đã hội tụ khá rõ:

1. **Đổi cơ số sang 2** rồi tách số mũ thành phần nguyên (→ phép dịch bit) và phần lẻ (→ đa thức bậc thấp hoặc bảng tuyến tính từng đoạn). Cả I-BERT, Shiftmax (I-ViT) lẫn Softermax đều dùng biến thể của ý này.
2. **Một phép nghịch đảo cho mỗi vector**, sau đó nhân cho từng phần tử. Chia trực tiếp từng phần tử là lựa chọn tồi.
3. **Online normalization** (Milakov & Gimelshein 2018) gộp lượt tìm max và lượt cộng tổng; khi dùng cơ số 2 và **max nguyên** (Softermax) thì bước hiệu chỉnh tổng chỉ là một phép dịch.

**Đề xuất kiến trúc cho BTL** (chi tiết ở mục 5): pipeline P lane theo khuôn Softermax (Unnormed Softmax Unit + Normalization Unit), nhưng thay giả định "mô hình đã fine-tune theo cơ số 2" bằng **một hệ số scale lập trình được nhân trên DSP**, để accelerator tính đúng `exp` (cơ số e) cho mọi scale lượng tử hoá mà không cần huấn luyện lại. Hàm 2^frac dùng PWL tham số hoá số đoạn; nghịch đảo dùng bộ chia tuần tự một lần mỗi hàng. Cấu hình mặc định đề xuất: **P = 8 lane, L_MAX = 512, đầu vào INT8, đầu ra UINT8**.

## 2. Bối cảnh: vì sao softmax là nút thắt

- Trong self-attention, mỗi lớp gồm các phép nhân ma trận và softmax; Softermax cho thấy trên GPU, softmax chiếm tỷ lệ thời gian chạy lớn hơn hẳn so với các mạng khác, và tỷ lệ này tăng theo độ dài chuỗi (đo trên BERT-Large, GPU Volta).
- Các accelerator trước đây tối ưu cho CNN/MLP/LSTM nên gần như bỏ qua softmax, vì ở các mạng đó softmax chỉ xuất hiện ở lớp cuối.
- Softermax nêu hai nguyên nhân làm softmax kém hiệu quả trên phần cứng: hàm mũ cần LUT lớn để đạt độ chính xác cao, và phiên bản ổn định số học cần thêm một lượt quét để tìm max.
- Survey FPGA gần đây (2026) cũng xác nhận softmax gây chi phí đáng kể về điều khiển và datapath trên FPGA, do phép rút gọn và các hàm phi tuyến.

Hệ quả cho báo cáo: đề tài bổ sung đúng phần mà các accelerator GEMM (nhóm 2, 5, 8, 9) bỏ lại.

## 3. Thuật toán

### 3.1. Softmax ổn định số học và online normalization

Softmax chuẩn: `y_i = exp(x_i − m) / Σ_j exp(x_j − m)`, với `m = max(x)`. Cách ngây thơ cần 3 lượt (max, tổng, chuẩn hoá).

**Online normalizer** (Milakov & Gimelshein, NVIDIA, 2018): duy trì max tạm `m_j` và tổng tạm `d_j` trong một lượt:

```
m_j = max(m_{j-1}, x_j)
d_j = d_{j-1} · exp(m_{j-1} − m_j) + exp(x_j − m_j)
y_i = exp(x_i − m_V) / d_V        (lượt 2)
```

Bài gốc giảm số lần truy cập bộ nhớ từ 4 xuống 3 cho mỗi phần tử, và đo được softmax nhanh hơn tới 1,3× trên GPU. Phép kết hợp `⊕` trên cặp (m, d) có tính kết hợp, nên tính song song theo lane rồi gộp được — quan trọng cho thiết kế P lane.

### 3.2. I-BERT: i-exp bằng đa thức bậc 2 (Kim et al., ICML 2021)

- Sau khi trừ max, đầu vào không dương; phân tích `x̃ = −z·ln2 + p` với `z` nguyên ≥ 0 và `p ∈ (−ln2, 0]`, nên `exp(x̃) = exp(p) >> z`.
- `exp(p)` trên đoạn hẹp được xấp xỉ bằng `L(p) = 0.3585(p + 1.353)² + 0.344`, sai số lớn nhất 1,9×10⁻³ — nhỏ hơn sai số lượng tử hoá 8 bit (1/256 ≈ 3,9×10⁻³).
- Các phép phi tuyến tính trên kết quả cộng dồn INT32 rồi requantize về INT8; tác giả ghi nhận giữ INT32 cho phần phi tuyến là quan trọng để không mất độ chính xác.
- Phép chia: `q_exp / sum(q_exp)` — bài không nói cách hiện thực phần cứng.
- **Chi phí phần cứng:** cần phép chia nguyên `z = ⌊−q / q_ln2⌋` cho mỗi phần tử (hoặc nhân với hằng nghịch đảo), một phép bình phương và các phép cộng. Trên FPGA, bình phương dùng DSP.

### 3.3. Shiftmax (I-ViT, Li & Gu, ICCV 2023)

- Đổi cơ số: `log2(e) ≈ 1.0111₂`, nên `x·log2e ≈ x + (x>>1) − (x>>4)` — chỉ dùng phép dịch và cộng.
- Tách phần nguyên `q` (dịch) và phần lẻ trong `(−1, 0]`; xấp xỉ `2^(lẻ)` bằng **hàm tuyến tính** `lẻ/2 + 1` — thô hơn I-BERT nhưng rẻ hơn nhiều.
- Phép chia: `I_out = (⌊2^M / Σ I_exp⌋ · I_exp) >> (M − (k_out − 1))`, tức **một phép chia nguyên cho cả vector**, sau đó mỗi phần tử là một phép nhân và dịch. Đầu ra có scale cố định `1/2^(k_out−1)`.
- Ngoài một phép trừ, phép cộng tổng và phép chia, mọi thứ là dịch bit.
- **Lưu ý:** xấp xỉ `log2e` bằng 3 số hạng dịch có sai số tương đối khoảng 0,36% (1,4375 so với 1,4427) — cần mô hình sai số này trong golden model.

### 3.4. Softermax (Stevens et al., DAC 2021) — tham chiếu kiến trúc chính

Bốn thay đổi so với softmax chuẩn:
1. **Thay cơ số e bằng 2** (dùng thẳng `2^x`, chấp nhận khác biệt và bù bằng fine-tune).
2. **Tính toán độ chính xác thấp, fixed-point** cho mũ, cộng dồn và chia.
3. **Online normalization** với **IntMax**: lấy trần (ceil) các phần tử trước khi tìm max, nên hiệu giữa các max luôn là số nguyên → hiệu chỉnh tổng chỉ là phép dịch.
4. **Softermax-aware fine-tuning** để bù sai số.

Phần cứng gồm hai khối:
- **Unnormed Softmax Unit:** IntMax → Power-of-Two (phần nguyên dịch, phần lẻ qua **PWL 4 đoạn**) → Reduction (cây cộng + đọc/ghi running max/sum, hiệu chỉnh bằng dịch).
- **Normalization Unit:** hiệu chỉnh tử số theo max toàn cục bằng dịch, rồi nhân với nghịch đảo từ **PWL reciprocal unit** + bộ nhân nguyên. Khối này có thể dùng chung cho nhiều PE.

Định dạng bit (Q(nguyên, lẻ)):

| Input | LocalMax | Unnormed | PowSum | Recip | Output |
|-------|----------|----------|--------|-------|--------|
| Q(6,2) | Q(6,2) | Q(1,15) | Q(10,6) | Q(1,7) | Q(1,7) |

Kết quả: độ chính xác GLUE/SQuAD không giảm trung bình (tệ nhất < 0,5%) sau fine-tune; Unnormed Softmax Unit nhỏ hơn 4× và tiết kiệm năng lượng 9,53× so với baseline DesignWare FP16; ở mức PE, hiệu quả năng lượng 2,35× với 0,90× diện tích (TSMC 7nm).

**Hạn chế cần lưu ý cho BTL:** việc thay hẳn cơ số e bằng 2 đòi hỏi mô hình được fine-tune theo Softermax. Demo của chúng ta không fine-tune mô hình, nên không nên phụ thuộc giả định này (xem mục 5.2).

### 3.5. Các hướng khác (để so sánh trong báo cáo)

- **Log-sum-exp** (Wang et al., APCCAS 2018): biến phép chia thành phép trừ, `y = exp(x − m − ln Σ exp(x − m))`; dùng biến đổi cơ số 2 cho cả exp và ln, không cần bộ nhân thông thường lẫn LUT. Tổng hợp TSMC 28nm đạt 6,976 G/s cho dữ liệu 8 bit, diện tích 0,015 mm². Nhược điểm: cần thêm khối log và một exp thứ hai ở đầu ra.
- **SoftGen** (Wei et al., ASAP 2020, UT Austin): generator softmax tham số hoá theo song song, độ chính xác, độ chính xác số, lưu trữ. Kết quả: song song 16 cho tích diện tích–trễ tốt nhất trong khoảng 1–32; exp/log bằng LUT đạt độ chính xác gần như bản đầy đủ nhưng tiết kiệm diện tích và năng lượng. Cách dọn đầu vào: coi giá trị nhỏ hơn −8 (sau khi trừ max) là bằng phần tử cuối LUT vì `e^−8 ≈ 3,35×10⁻⁴`.
- **SOLE / E2Softmax** (Wang et al., 2025): lượng tử hoá log2 của hàm mũ và phép chia dựa trên log; không cần huấn luyện lại; báo cáo hiệu quả năng lượng 3,04× và hiệu quả diện tích 2,82× so với Softermax. Một bài MDPI 2026 nhận xét SOLE dựa vào bộ dịch động tốn tài nguyên trên FPGA.
- **PWL thuần LUT trên FPGA** (2026): exp xấp xỉ bằng PWL 16 đoạn trong LUTRAM, không dùng BRAM; lõi attention-row dùng 1444 LUT, 77 DSP, đạt 12,63 krows/s ở 100 MHz — là điểm so sánh tài nguyên tốt cho báo cáo (khác họ FPGA, cần ghi chú).
- **Đề cập lịch sử:** Yuan (SOCC 2016), Du et al. (GLSVLSI 2019, xử lý tuần tự với FIFO), Geng et al. (ACCV 2018), Hu et al. (2018, stochastic computing).

### 3.6. Bảng so sánh định tính

| Phương pháp | Hàm mũ | Phép chia | Số lượt | Cần fine-tune | Chi phí chính trên FPGA |
|---|---|---|---|---|---|
| I-BERT | đa thức bậc 2 + dịch | chia nguyên (không chi tiết) | 3 | Có (QAT) | DSP cho bình phương; chia cho `z` mỗi phần tử |
| Shiftmax | dịch + tuyến tính | 1 chia nguyên/vector | 3 | Có (QAT) | rất rẻ; sai số log2e cố định |
| Softermax | 2^x, PWL 4 đoạn | PWL reciprocal + nhân | 2 | Có | nhỏ; phụ thuộc cơ số 2 |
| Log-sum-exp | 2^x + ln | trừ | 3 | Không | thêm khối ln + exp thứ hai |
| SOLE | log2 lượng tử | dựa trên log | 2–3 | Không | bộ dịch động |

## 4. Bài học từ các thiết kế phần cứng

1. **Exp thô vẫn đủ:** PWL 4 đoạn (Softermax) hay tuyến tính 1 đoạn (Shiftmax) không làm giảm độ chính xác mô hình sau fine-tune; khi không fine-tune, nên tăng số đoạn (8–16) — đây là tham số đáng quét trong báo cáo.
2. **Chia một lần mỗi vector** là chuẩn chung; phần cứng chia có thể chậm.
3. **Song song theo lane có điểm tối ưu** (SoftGen: 16; trên FPGA nhỏ, 8 là hợp lý).
4. **Đọc lại từ bộ nhớ thay vì lưu thanh ghi** giữ diện tích không đổi theo độ dài vector; độ trễ đọc lại che được sau các phép khác (SoftGen).
5. **Định dạng đầu ra cố định scale** (`1/2^(k−1)`, Shiftmax) đơn giản hoá requantization phía sau.

## 5. Đề xuất kiến trúc cho BTL

### 5.1. Phạm vi một lần chạy

Accelerator tính softmax cho R hàng (R ≥ 1), mỗi hàng dài L phần tử (1 ≤ L ≤ L_MAX). HPS nạp ma trận điểm attention vào bộ đệm, ghi L, R, scale, chạy, poll DONE, đọc kết quả. Masking (cho decoder) là mở rộng tuỳ chọn.

### 5.2. Số học (đề xuất)

- **Đầu vào:** INT8 có dấu (điểm attention đã requantize). Tuỳ chọn mở rộng: INT16.
- **Scale lập trình được:** thanh ghi `SCALE_LOG2E` (UQ0.16 hoặc UQ2.14) chứa `K = S_in · log2(e)` tính sẵn phía HPS. Mỗi lane nhân **trực tiếp** `q` với K trên **một DSP** để có `u = K·q` (số mũ cơ số 2, fixed-point), **trước** khi tìm max — thứ tự này bắt buộc để IntMax (lấy trần của u) làm việc trên miền cơ số 2, nhờ đó hiệu chỉnh tổng online chỉ là phép dịch. Số mũ đưa vào khối 2^x là `u − M` với `M = ⌈max u⌉` nguyên. Lợi ích: tính đúng `exp` cơ số e với mọi scale, không cần fine-tune theo cơ số 2 (khác Softermax), và không chịu sai số cố định của xấp xỉ log2e bằng dịch (khác Shiftmax). Chi phí: P bộ nhân 8×16 — Cyclone V dư DSP.
- **2^frac:** PWL N_SEG đoạn trên [0,1), hệ số trong ROM nhỏ (N_SEG = 4/8/16 tham số hoá); phần nguyên → dịch phải. Giá trị dưới ngưỡng (ví dụ số mũ < −16) gán 0.
- **Max:** IntMax kiểu Softermax trên miền số mũ cơ số 2 để hiệu chỉnh tổng chỉ là phép dịch.
- **Tích luỹ:** tổng không dấu đủ rộng cho L_MAX (≥ log2(L_MAX) + 1 bit nguyên + 15–16 bit lẻ; với L_MAX = 512 → khoảng 25–26 bit).
- **Nghịch đảo:** `R = ⌊2^M / sum⌋` bằng **bộ chia tuần tự radix-2** (một lần mỗi hàng, ~26–32 chu kỳ) — chính xác, dễ verify. Phương án thay thế để so sánh: LUT + 1 vòng Newton–Raphson.
- **Đầu ra:** `y = (e_i · R) >> shift`, làm tròn, bão hoà về **UINT8 với scale 1/256** (hoặc Q1.7 như Softermax — cần chốt).

### 5.2b. Hằng số và bảng tra (không có hàm log nào trong datapath)

- `log2(e)` là hằng, gộp vào K do HPS tính bằng float một lần mỗi cấu hình scale → không cần bảng.
- Bảng duy nhất: hệ số PWL của `2^F`, F ∈ [0,1), N_SEG đoạn đều; chỉ số đoạn = log2(N_SEG) bit cao của F, phần còn lại r dùng cho `y = c[idx] + m[idx]·r` (1 phép nhân). Bảng sinh offline bằng script Python, đưa vào RTL dưới dạng hằng (`localparam` hoặc file .mif/.hex), tổng hợp thành logic/MLAB.
- Sai số nội suy dây cung trên đoạn độ rộng h: sai số tương đối ≤ h²/8 · (ln2)² (vì f''/f = (ln2)² ≈ 0,48) → kiểm tra số: 0,38% (N=4), 0,094% (N=8), 0,023% (N=16); phương án minimax giảm khoảng một nửa.
- Ví dụ số (đã kiểm bằng Python): S = 0,0625 → K = round(S·log2e·2¹⁶) = 5909. Hàng có q_max = 40, q_i = 20: u_max = 3,6066, M = 4; u_i − M = −2,1967 → I = −3, F = 0,8033 → 2^F = 1,745, dịch phải 3 → 0,2181; phần tử max cho 2^(−0,3934) = 0,7613; tỉ số 0,2865 = e^(−1,25) = e^(S·(q_i − q_max)) — M nguyên triệt tiêu khi chuẩn hoá. Sai số lượng tử K (½ LSB) gây lệch số mũ tối đa ≈ 0,0019 khi |Δq| = 255, tức ≈ 0,13% đầu ra.
- Nghịch đảo: bộ chia tuần tự không cần bảng; nếu chọn Newton–Raphson thì cần một bảng seed nhỏ.
- So với CORDIC: CORDIC hyperbolic cần bảng hằng atanh(2^−i), dịch–cộng lặp ~1 vòng/bit (cộng vòng lặp lại để hội tụ) và vẫn cần thu hẹp miền; không dùng DSP nhưng tốn latency hoặc nhiều tầng pipeline. Trên Cyclone V dư DSP, PWL 1 phép nhân rẻ và nhanh hơn; CORDIC chỉ nên là phương án so sánh.

### 5.3. Datapath và điều khiển

```
           pass 1 (đọc X)                              pass 2 (đọc X lần nữa)
X_BUF ──► [×K (DSP)] ─► [IntMax online] ─► [−M, 2^x: shift+PWL] ─► [Σ, hiệu chỉnh bằng dịch]
                                                         │ M_final, sum
                                                         ▼
                                                   [reciprocal (seq. divider)]
                                                         │ R
X_BUF ──► [×K] ─► [−M_final, 2^x] ─► [× R, round, sat] ─► Y_BUF
```

- **P lane** đọc P phần tử/chu kỳ từ X_BUF (M10K rộng P×8 bit). Lượt 1 dùng online normalization, mỗi lane giữ (m, d) riêng rồi gộp bằng toán tử ⊕ ở cuối hàng.
- **Lượt 2 tính lại exp** thay vì lưu exp chưa chuẩn hoá: không cần buffer trung gian rộng, đổi lại tốn lại logic exp (đã có sẵn) — theo bài học SoftGen. Phương án Softermax (lưu unnormed + dịch hiệu chỉnh) để làm ablation nếu dư thời gian.
- Chồng lặp: bộ chia của hàng r có thể chạy song song với lượt 1 của hàng r+1 (mở rộng tuỳ chọn).
- **Latency ước tính mỗi hàng:** ≈ 2·⌈L/P⌉ + T_div + độ sâu pipeline. Với L = 512, P = 8: ≈ 64 + 64 + 32 + ~10 ≈ 170 chu kỳ.

### 5.4. Tài nguyên ước tính (P = 8)

Mỗi lane: bộ trừ 9 bit, bộ nhân scale, bộ dịch ~24 bit, PWL (ROM nhỏ + bộ nhân), so sánh, cộng, và bộ nhân đầu ra `e_i · R`; cộng thêm cây cộng/so sánh 8 đầu vào, bộ chia, controller, Avalon wrapper. Tổng cộng khoảng 24 bộ nhân (3 mỗi lane), tương đương khoảng 12–24 khối DSP tuỳ độ rộng toán hạng, cộng **vài nghìn ALUT** — vượt ngưỡng 1000 LUT với biên rộng. Cần xác nhận bằng tổng hợp thực tế.

### 5.5. Kế hoạch đánh giá cho báo cáo

- **Đúng bit:** RTL so khớp golden model NumPy mô phỏng chính xác từng tầng fixed-point.
- **Độ chính xác số học:** sai số tuyệt đối lớn nhất, sai số trung bình, KL-divergence so với softmax float64, quét theo N_SEG (4/8/16), độ rộng phần lẻ, L.
- **So sánh thuật toán (phần mềm):** cùng tập vector, so sai số giữa I-BERT, Shiftmax, Softermax (cơ số 2 không fine-tune) và thiết kế của mình.
- **Phần cứng:** ALUT/register/DSP/M10K, Fmax, chu kỳ/hàng (CYCLE_CNT), throughput phần tử/chu kỳ; quét P = 4/8/16.

## 6. Các quyết định cần chốt (đưa vào PROJECT.md)

1. Độ rộng đầu vào: INT8 (đề xuất) hay INT16?
2. Định dạng đầu ra: UINT8 scale 1/256 hay Q1.7 (Softermax)?
3. P (đề xuất 8) và L_MAX (đề xuất 512); có hỗ trợ nhiều hàng R trong một lần chạy không?
4. Lượt 2 tính lại exp (đề xuất) hay lưu unnormed?
5. Nghịch đảo: bộ chia tuần tự (đề xuất) hay LUT + Newton–Raphson?
6. N_SEG mặc định của PWL (đề xuất 8, tham số hoá).
7. Masking có nằm trong phạm vi không (đề xuất: không, để mở rộng).

## 7. Tài liệu tham khảo

1. M. Milakov, N. Gimelshein, "Online normalizer calculation for softmax", arXiv:1805.02867, 2018. https://arxiv.org/abs/1805.02867
2. S. Kim, A. Gholami, Z. Yao, M. W. Mahoney, K. Keutzer, "I-BERT: Integer-only BERT Quantization", ICML 2021. https://arxiv.org/abs/2101.01321
3. J. R. Stevens, R. Venkatesan, S. Dai, B. Khailany, A. Raghunathan, "Softermax: Hardware/Software Co-Design of an Efficient Softmax for Transformers", DAC 2021. https://arxiv.org/abs/2103.09301
4. Z. Li, Q. Gu, "I-ViT: Integer-only Quantization for Efficient Vision Transformer Inference", ICCV 2023. https://arxiv.org/abs/2207.01405
5. M. Wang, S. Lu, D. Zhu, J. Lin, Z. Wang, "A High-Speed and Low-Complexity Architecture for Softmax Function in Deep Learning", APCCAS 2018. https://ieeexplore.ieee.org/document/8605654
6. Z. Wei, A. Arora, P. Patel, L. John, "Design Space Exploration for Softmax Implementations", ASAP 2020. https://labs.engineering.asu.edu/advent/wp-content/uploads/sites/123/2023/09/SoftMax___ASAP2020_June14.pdf
7. G. Du et al., "Efficient Softmax Hardware Architecture for Deep Neural Networks", GLSVLSI 2019. https://doi.org/10.1145/3299874.3317988
8. W. Wang, S. Zhou, W. Sun, P. Sun, Y. Liu, "SOLE: Hardware-Software Co-design of Softmax and LayerNorm for Efficient Transformer Inference", arXiv:2510.17189, 2025. https://arxiv.org/abs/2510.17189
9. S. Lu et al., "Hardware Accelerator for Multi-Head Attention and Position-Wise Feed-Forward in the Transformer", arXiv:2009.08605 (SOCC 2020). https://arxiv.org/abs/2009.08605
10. "Approximate Attention Weighting for Sustainable FPGA-Based Vision Transformer Inference", arXiv:2607.01798, 2026. https://www.emergentmind.com/papers/2607.01798
11. "Recent Developments in Transformer Inference Deployment on FPGA Platforms: A Survey", arXiv:2609.01212, 2026. https://arxiv.org/pdf/2609.01212
12. B. Yuan, "Efficient hardware architecture of softmax layer in deep neural network", SOCC 2016 (tham khảo qua [6]).
13. H. Touvron, M. Cord, M. Douze, F. Massa, A. Sablayrolles, H. Jégou, "Training data-efficient image transformers & distillation through attention" (DeiT), ICML 2021. https://arxiv.org/abs/2012.12877 — mô hình target của project (D18, `docs/spec/02-target-workload.md`).
