# CONVENTIONS — quy ước báo cáo, hình và công cụ

## Báo cáo

- Nguồn: `docs/report/` dùng LaTeX, mỗi chương một file trong `docs/report/chapters/`. Chỉnh chương nào thì sửa file đó.
- Biên dịch bằng XeLaTeX (hỗ trợ tiếng Việt và Times New Roman):
  ```bash
  cd docs/report && xelatex main.tex && xelatex main.tex
  ```
- Format:
  - Font Times New Roman (fallback Liberation Serif), cỡ 13 pt.
  - Giãn dòng 1.5, khoảng cách đoạn: trước 6 pt, sau 0 pt. Thụt đầu dòng 1,25 cm (giả định, chỉnh trong `main.tex` nếu khác).
  - Lề: trái 3 cm, phải 2 cm, trên 2,5 cm, dưới 2,5 cm.
- Số liệu chưa đo thì ghi `[Chưa đo]`, không điền ước lượng vào bảng kết quả.

## Hình

- Đặt trong `docs/figures/`. Định dạng PDF hoặc SVG cho sơ đồ; PNG cho ảnh chụp, đồ thị sinh từ script.
- Tên file: `<khối>_<nội dung>.pdf`, ví dụ `smx_sumacc_pipeline.pdf`.
- Đồ thị số liệu sinh bằng matplotlib từ script đặt trong `scripts/`, lưu cùng tên vào `docs/figures/`.
- Trong LaTeX, `\graphicspath` đã trỏ tới `docs/figures/`, chỉ cần `\includegraphics{ten_file}`.

## Công cụ vẽ

- Sơ đồ khối, FSM, sequence: mermaid trong markdown. Khi đưa vào báo cáo, xuất sang PDF hoặc SVG rồi đặt vào `docs/figures/`.
- Dạng sóng và timing: WaveDrom JSON trong `docs/spec/wave/`.
- Đồ thị số liệu: matplotlib.

## Trạng thái giữa các phiên

- Trạng thái công việc ghi tại `docs/spec/blocks/README.md` (bảng block) và `docs/PROJECT.md` mục 10 (nhật ký).
