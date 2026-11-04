# Target workload — DeiT-Tiny (D18)

> Trạng thái: **CHỐT 2026-10-31** (Chau duyệt; quyết định D18 trong `docs/PROJECT.md` mục 7). Tài liệu này mô tả *mạng nào* dùng `smx` và *đánh giá thế nào*; nó **không** đổi requirements v1.0 hay giao diện (HW_PARAM VERSION giữ 0x10).
> Ký hiệu nguồn như `PROJECT.md` mục 7.1: [TL] tài liệu công bố, [GM] đo bằng golden model, [TK] ước lượng/lựa chọn thiết kế, [ĐC] kiến thức chung cần đối chiếu.

## 1. Quyết định

Workload mục tiêu duy nhất của project là **softmax trong multi-head self-attention của DeiT-Tiny** (`deit_tiny_patch16_224`, bản không distill), phân loại ảnh ImageNet-1k. Dùng cho cả hai việc: đánh giá độ chính xác ở mức mạng trong báo cáo và demo hardware-in-the-loop trên DE10-Standard. Không làm workload thứ hai (DistilBERT, GPT-2, … đã cân nhắc, xem mục 7).

Lý do:

1. **Khớp requirements v1.0 nguyên trạng.** ViT không dùng attention mask (B6), L = 197 ≤ L_MAX = 512, mỗi head một scale nên một lần chạy dùng một K.
2. **Có mốc so sánh trong tài liệu.** I-ViT [4] báo cáo kết quả integer-only trên DeiT-T, nên có thể đặt phép softmax của project cạnh Shiftmax trên cùng mô hình.
3. **Corner tự nhiên.** L = 197 = 24·8 + 5: nhóm cuối của mỗi hàng chỉ có 5 lane hợp lệ, kiểm lane mask bằng dữ liệu thật.
4. **Nhẹ phía host.** ~5M tham số, chạy được trên PC bằng CPU; nếu sau này đi đường GHRD + Linux, vẫn khả thi trên Cortex-A9 hơn các mô hình 100M+ tham số.

## 2. Mô hình

| Thông số | Giá trị | Nguồn |
|---|---|---|
| Kiến trúc | ViT, 12 encoder block, MHSA + MLP, pre-LayerNorm | [TL] DeiT [13] — cần đối chiếu |
| Kích thước ảnh, patch | 224×224, patch 16×16 → 14×14 = 196 patch | [ĐC] |
| Số token L | 196 + 1 [CLS] = **197** (bản distill có thêm token distill → 198, **không dùng**) | [ĐC] |
| Embedding, số head, head dim | 192, **3**, 64 | [TL] [13] bảng 1 — cần đối chiếu |
| Tham số | ~5M | [TL] [13] bảng 1 — cần đối chiếu |
| Top-1 ImageNet (FP32) | ~72,2 % | [TL] [13] — cần đối chiếu |
| Trọng số | `timm`, tên `deit_tiny_patch16_224` | [ĐC] |

Softmax trong mỗi block: `A = softmax(Q·Kᵀ · 64^(−1/2))` theo hàng, kích thước 3 × 197 × 197 mỗi ảnh.

## 3. Ánh xạ lên `smx`

Một **hàng** của `smx` = một query token i của một head h trong một layer ℓ: 197 điểm `s[ℓ,h,i,0..196]`.

| Đại lượng | Giá trị | Ghi chú |
|---|---|---|
| LEN | 197 | không đổi trong mọi lần chạy |
| ROWS | 16 (lần cuối mỗi head: 5) | 197 = 12·16 + 5 → 13 lần chạy / head |
| Lần chạy / layer / ảnh | 3 × 13 = 39 | mỗi lần chạy chỉ chứa hàng của **một** head → một K |
| Hàng / layer / ảnh | 3 × 197 = 591 | |
| Nhóm P = 8 / hàng | ⌈197/8⌉ = 25, nhóm cuối 5 lane | |
| Chu kỳ / hàng | 2·25 + 54 = 104; trần REQ-PRF-03: 2·25 + 64 = 114 | đo bằng `CYCLE_CNT` trong `tb_smx_core`, gồm mọi L ở P = 8 |
| Chu kỳ / layer / ảnh | 591 × 104 + 39 = 61 503 (≈ 0,62 ms @ 100 MHz) | tính từ công thức `CYCLE_CNT = R·T_row + 1` đã kiểm bằng mô phỏng; chưa đo trên board |
| Dữ liệu JTAG / layer / ảnh | ghi ⌈197/4⌉ = 50 word/hàng, đọc 50 word/hàng → 591 × 400 B ≈ 231 KiB | [TK]; X_BUF stride 512 B/hàng nhưng chỉ ghi 50 word đầu |

Với băng thông JTAG cỡ chục–trăm KB/s (`integration-notes.md`, chưa đo), một layer của một ảnh mất cỡ giây đến chục giây trên board. Chấp nhận được cho demo vài ảnh; **không** chạy cả tập dữ liệu trên board (xem mục 5).

## 4. Lượng tử hoá đầu vào của softmax

Chỉ phép softmax là integer. Phần còn lại của DeiT-Tiny giữ FP32 trên host; project không lượng tử hoá toàn mạng (ngoài phạm vi, `requirements.md` mục 1).

1. Host tính điểm `s = (Q·Kᵀ)/8` ở FP32 như mô hình gốc.
2. Scale đối xứng theo **(layer, head)**: `S[ℓ,h] = max|s| / 127`, lấy trên một tập hiệu chuẩn (calibration) nhỏ. Một lần chạy chỉ chứa một head nên scale theo head không tốn gì thêm về phần cứng.
3. `q = clamp(round(s / S), −128, 127)`; `K = round(S·log₂e·2¹⁶)` ghi vào `SCALE_K` (REQ-ARI-02).
4. Ràng buộc `0 < S < ~0,693` ⇔ `max|s| < ~88`. **Phải đo** trên tập hiệu chuẩn cho cả 36 cặp (ℓ, h); nếu vi phạm thì kẹp S (chấp nhận bão hoà điểm) và ghi lại.
5. Đầu ra `y` (UINT8) đổi lại `A = y / 256` (FP32) cho phép `A·V` phía host.

Cách hiệu chuẩn (max hay percentile) và kích thước tập hiệu chuẩn là câu hỏi mở (mục 8); mặc định dùng max.

## 5. Đánh giá

Vì RTL khớp golden model bit-exact (REQ-VER-01), độ chính xác đo bằng golden model trên host **chính là** độ chính xác của phần cứng. Board chỉ cần chứng minh sự tương đương trên một số mẫu.

| Mã | Thí nghiệm | Chạy ở đâu | Đầu ra cho báo cáo |
|---|---|---|---|
| E1 | Top-1 toàn mạng với ba cấu hình softmax ở **cả 12 layer**: (a) FP32 gốc; (b) điểm lượng tử hoá INT8 + softmax float; (c) điểm INT8 + `smx` (golden). Lặp (c) với N_SEG = 4/8/16. | PC, golden model | Tách sai số do lượng tử hoá điểm (b − a) và do `smx` (c − b); so với số DeiT-T của I-ViT [4] (lưu ý I-ViT lượng tử hoá toàn mạng, không so ngang hàng) |
| E2 | Thống kê theo layer/head: S, max\|s\|, sai số tuyệt đối của A so với softmax float, tỉ lệ phần tử bão hoà 255 | PC, golden model | Bảng/biểu đồ theo layer |
| E3 | Hardware-in-the-loop: một vài ảnh, softmax của một layer ℓ chạy trên board, các layer khác dùng golden. Kiểm Y_BUF == golden bit-exact, nhãn dự đoán khớp, `CYCLE_CNT` khớp latency micro-arch | DE10 qua JTAG | Demo + bằng chứng tương đương; số chu kỳ thật thay cho [TK] ở mục 3 |

## 6. Hệ quả cho thực hiện

- **Requirements, giao diện, RTL:** không đổi. VERSION giữ 0x10.
- **Verification:** thêm vector thật L = 197 trích từ DeiT-Tiny vào `tb/vectors/`, bên cạnh danh sách REQ-VER-02 (không đổi requirement, chỉ bổ sung kế hoạch test).
- **`model/`:** `softmax_row` là vòng lặp Python thuần, quá chậm cho E1 (ImageNet val đầy đủ: 50 000 × 12 × 591 ≈ 3,5·10⁸ hàng). Cần thêm bản vector hoá (NumPy/PyTorch int64) và **kiểm chéo bit-exact** với `softmax_row` trên vector ngẫu nhiên + corner trước khi dùng.
- **Móc vào mô hình:** thay `forward` của khối attention trong `timm` để lấy `s` và trả `A`. Các bản `timm` mới dùng fused attention (`scaled_dot_product_attention`), cần tắt để lấy được ma trận điểm — cách tắt tuỳ phiên bản, cần đối chiếu.
- **Môi trường:** cài `torch`, `timm` vào `~/venvs/ml`; cần dữ liệu ImageNet-1k val hoặc tập con (mục 8).
- **Nhóm implement:** script demo (integration-notes mục 1.4) sẽ lấy vector từ DeiT-Tiny thay vì ngẫu nhiên; nên đo sớm băng thông JTAG thật để ước lượng thời gian demo E3.

## 7. Phương án đã cân nhắc

Phân tích ngày 2026-10-31. Byte/layer = heads × L × L × 2 (vào + ra), tính thô.

| Phương án | Hình dạng softmax | Khớp v1.0 | Byte/layer | Lý do không chọn |
|---|---|---|---|---|
| B. ViT nhỏ tự train, CIFAR-10 (L = 65) | tự chọn | có | ≈ 34 KB | Dễ nhất nhưng không có mốc so sánh; dễ bị coi là mô hình đồ chơi |
| C. DistilBERT SST-2 | 12 head, L ≈ 20–60 | có nếu batch 1, LEN = độ dài câu | ≈ 25 KB (L = 32) | Demo trực quan nhưng L ngắn, không có mốc integer-softmax trên đúng mô hình |
| D. BERT-base / I-BERT RoBERTa | 12 head, L = 128–512 | batch có padding cần mask | 0,4–3,5 MB | Phải fine-tune, dữ liệu JTAG lớn, logit có outlier |
| E. GPT-2 small, bước decode | 12 head × 1 hàng, L = t | có (decode không cần mask); prefill cần mask | ≈ 6 KB/token (t = 256) | Context bị chặn 512; prefill phức tạp; không có mốc |
| F. Swin-T window attention | 3 head, L = 49 | không: block shifted-window cần mask (mở lại B6) | ≈ 920 KB (stage 1) | Phải đổi requirements |
| G. KWT, Speech Commands | L ≈ 99 (cần đối chiếu) | có | ≈ 20 KB | Ít phổ biến; trọng số pretrained chưa chắc có sẵn |

## 8. Câu hỏi mở

- [ ] Dữ liệu đánh giá E1: ImageNet-1k val đầy đủ (cần đăng ký tải) hay một tập con (bao nhiêu ảnh, chọn thế nào)?
- [ ] Hiệu chuẩn S: max hay percentile; tập hiệu chuẩn bao nhiêu ảnh?
- [ ] Ràng buộc `max|s| < ~88` có thoả ở mọi (layer, head) không? (đo trước khi chạy E1)
- [ ] Layer nào chạy trên board ở E3, và bao nhiêu ảnh?
- [ ] Băng thông JTAG thật (nhóm implement đo).

## 9. Tham khảo

Số trong ngoặc vuông theo `docs/research/softmax-survey.md` mục 7. Chính: [4] I-ViT (mốc so sánh trên DeiT-T), [13] DeiT (mô hình target).
