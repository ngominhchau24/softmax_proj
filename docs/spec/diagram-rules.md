# Quy tắc vẽ sơ đồ

Sơ đồ khối của project theo kiểu sơ đồ trong bài báo vi mạch: khối vuông, dây thẳng bẻ góc vuông, nhãn tín hiệu nằm cạnh dây. Áp dụng cho mọi sơ đồ cấu trúc và FSM trong `docs/`, kể cả trang artifact.

## 1. Công cụ

| Loại hình | Công cụ | Nơi lưu |
|---|---|---|
| Sơ đồ cấu trúc, datapath, FSM | SVG sinh từ script đặt vị trí bằng tay | `docs/spec/fig/<tên>.py` và `<tên>.svg` |
| Dạng sóng, timing chu kỳ | WaveDrom | `docs/spec/wave/<tên>.json` |
| Sequence giữa các bên | Mermaid `sequenceDiagram`, vì vốn chỉ có đường thẳng | Trong markdown |

**Không dùng Mermaid `flowchart` hay `stateDiagram` cho hình mới.** Đã thử Mermaid 12.2 với `look: classic` và `curve: stepAfter`: bẻ được góc vuông, nhưng bố trí tự động làm các dây chạy trùng nhau, nên không đọc được dây nào đi đâu, và nhãn nằm đè lên dây. Rule ở mục 2 đòi hỏi đặt tay, nên công cụ cũng phải đặt tay được.

Cách dùng:

```bash
python3 docs/spec/fig/<tên>.py       # sinh <tên>.svg; báo lỗi và không ghi nếu vi phạm rule tự kiểm được
```

Trong markdown: `![smx_core](fig/smx_core.svg)` (đường dẫn tương đối theo file). Commit cả `.py` và `.svg`. Sửa file `.py`, không sửa tay file `.svg`. `docs/spec/fig/schematic.py` chỉ dùng thư viện chuẩn của Python.

## 2. Quy tắc

**Dây**

1. Dây chỉ nằm ngang hoặc thẳng đứng, chỗ bẻ là góc vuông sắc. Không có đường cong, đường chéo, góc bo.
2. Mũi tên đặc, nhỏ, chỉ ở đầu đích. Dây hai chiều vẽ thành hai dây.
3. Hai dây không chạy chồng lên nhau trên cùng một đoạn.
4. Dây đi vòng quanh khối, không đi xuyên khối.
5. Rẽ nhánh có chấm tròn đặc ở điểm rẽ. Hai dây cắt nhau không có chấm là không nối.
6. Bus vẽ nét đậm hơn dây đơn, và ghi độ rộng trong nhãn, ví dụ `acc_writedata[31:0]` hoặc `q x P`.
7. Nên ít điểm bẻ và ít chỗ cắt nhau nhất có thể. Dây song song cách đều.

**Khối**

8. Khối là hình chữ nhật góc vuông, viền đen, nền trắng. Không tô màu, không bóng đổ, không gradient, không icon.
9. Khối cùng loại có cùng kích thước, và các khối cùng tầng căn thẳng hàng.
10. Dòng đầu trong khối là tên module đúng như trong RTL. Dòng thứ hai, nếu có, ghi vai trò ngắn hoặc số bản như `x P`.
11. Biên phân cấp là hình chữ nhật nét đứt, tên đặt bên trong ở góc dưới trái.

**Nhãn**

12. Nhãn tín hiệu dùng đúng tên trong RTL. Nhãn đặt phía trên dây ngang và bên phải dây đứng, không đè lên dây.
13. Một font sans-serif, chỉ hai cỡ chữ: tên khối và nhãn dây. Chữ đen, không in đậm để nhấn.

**Bố trí**

14. Luồng dữ liệu đi từ trái sang phải hoặc từ trên xuống. Chỉ đi ngược chiều với đường hồi tiếp hoặc khi không còn chỗ.
15. Port của khối nằm ở cạnh ngoài hình: đầu vào bên trái, đầu ra bên phải. Riêng cổng bus slave có cả đọc và ghi thì đặt cùng một cạnh.
16. Mọi toạ độ nằm trên lưới 10 px.
17. Phần lặp lại vẽ bản đầu, bản cuối và dấu ba chấm, kèm chỉ số, ví dụ `EC 0,0 ... EC 15,0`. Nếu cấu trúc các bản giống hệt nhau, được vẽ một khối và ghi `x P`.
18. Tín hiệu đi tới rất nhiều khối thì ghi nhãn đích thay vì kéo dây tới từng khối. `clk`, `rst_n` không vẽ, và có một dòng ghi chú trong hình.
19. Nền luôn trắng ở cả giao diện sáng và tối, vì nét đen không đọc được trên nền tối. Khi đưa vào trang tối thì đặt trong khung nền trắng.

**FSM**

20. Mỗi trạng thái là một khối vuông, chuyển trạng thái là dây vuông góc có mũi tên, nhãn ghi điều kiện và hành động. Không dùng bong bóng hay cung cong.

## 3. Những gì script tự kiểm

`save()` từ chối ghi file nếu có một trong các lỗi sau:

| Lỗi | Rule |
|---|---|
| Dây chéo | 1 |
| Hai dây khác nhau chồng lên cùng đoạn | 3 |
| Dây đi xuyên khối | 4 |
| Toạ độ lệch lưới | 16 |
| Mũi tên kết thúc giữa khoảng trống, trừ khi khai báo là chân ra | 2, 15 |
| Nhãn nằm đè lên dây hoặc khối, ước lượng theo độ dài chữ | 12 |

Các rule còn lại là chuyện trình bày, nên phải mở hình ra nhìn trước khi commit. Chấm rẽ nhánh ở rule 5 script không tự kiểm, phải đọc lại.

## 4. Trạng thái áp dụng

| Hình | Trạng thái |
|---|---|
| `fig/smx_core.svg`, dùng trong `design-spec.md` mục 2.2 | Đã theo rule, là hình mẫu |
| Các sơ đồ Mermaid hiện có trong `docs/spec/` và `docs/spec/blocks/` | Chưa chuyển |

Hình mới phải theo rule này ngay. Hình cũ chuyển khi Chau yêu cầu, hoặc khi sửa đáng kể tài liệu chứa hình đó.
