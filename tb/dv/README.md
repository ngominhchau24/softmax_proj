# tb/dv — môi trường DV cho `smx_core`

Verification chính thức của nhóm DV, tách khỏi các testbench tự kiểm của người thiết kế (`tb/tb_smx_*.sv`). DUT là `smx_core`, chỉ lái qua cổng `acc_*` (REQ-IF-06). Simulator: ModelSim Intel FPGA Edition 10.5b, nên không dùng UVM, SVA đồng thời hay `covergroup`; checker viết bằng `always` thủ tục và coverage bằng bộ đếm.

## Thành phần

| File | Vai trò |
|---|---|
| `smx_dv_pkg.sv` | Địa chỉ thanh ghi, giới hạn, hằng timing, công thức latency. Chép từ `docs/requirements.md` và `docs/spec/05-cross-block.md`, cố ý **không** import `smx_pkg`: RTL lệch khỏi tài liệu thì test phải fail |
| `smx_acc_bfm.sv` | BFM cổng `acc_*`: `write`, `read`, `read_burst`, `idle`. Lệnh lái ở cạnh xuống, dữ liệu đọc về sau 2 chu kỳ |
| `smx_scoreboard.sv` | Đọc vector golden từng run, đếm phép so và lỗi, in dòng `TB_RESULT` |
| `smx_core_chk.sv` | Checker giao thức REQ-VER-03, 8 luật R1–R8 xét từng chu kỳ trên port của DUT |
| `smx_core_bind.sv` | `bind` checker vào `smx_core` thành `dut.u_dv_chk`; chỉ có hiệu lực trong testbench dùng `smx_dv_env` |
| `smx_dv_env.sv` | Clock, reset, DUT, BFM, scoreboard, bind và các trình tự dùng chung: `init`, `program_run`, `start_run`, `wait_done`, `check_y`, `run_and_check`, `finish` |
| `../../model/dv_common.py` | Ghi file vector; số học lấy từ `softmax_ref.softmax_row` |
| `../../model/vec_dv_<test>.py` | Chọn kích thích cho từng test |

Một testcase là một module top `tb/tb_smx_dv_<test>.sv` khai báo `P`, `N_SEG`, tạo `smx_dv_env env ()` rồi gọi task của nó. Thêm test mới: viết file đó, thêm vào `sim/testcase.f` và vào `DV_TESTS` trong `sim/Makefile`, và nếu cần vector thì thêm `model/vec_dv_<test>.py` (`sim/Makefile` tự gọi).

## Danh sách test

| # | Test | REQ | Nội dung |
|---|---|---|---|
| 1 | `tb_smx_dv_sanity` | VER-01, FUN-01 | Giá trị reset, HW_PARAM, đọc ghi thanh ghi, 9 run cơ bản |
| 2 | `tb_smx_dv_ver02` | VER-01, VER-02, FUN-01/02/03 | Ma trận kiểu hàng × L × K, R = 1 và R_MAX, L_MAX với R_MAX. Hàng có L không chia hết cho P chạy hai lần: đuôi i ≥ L chứa rác (127, −128, ngẫu nhiên) rồi ghi kiểu phần mềm. Test tự kiểm kiểu của từng hàng và fail nếu thiếu bin coverage |
| 3 | `tb_smx_dv_proto` | VER-03, FUN-04, IF-09 | START với LEN/ROWS sai; START khi BUSY ở chu kỳ đầu, giữa, áp chót và cuối; START ngay chu kỳ DONE đầu tiên; ghi LEN, ROWS, SCALE_K, X_BUF, Y_BUF, STATUS, CYCLE_CNT khi BUSY; đọc STATUS và CYCLE_CNT khi BUSY |
| 4 | `tb_smx_dv_latency` | VER-04, PRF-03 | `CYCLE_CNT = R·(2·⌈L/P⌉ + 54) + 1` trên mọi L từ 1 tới 2P+2 và các mốc lớn, ba kiểu dữ liệu mỗi hình dạng (latency không phụ thuộc dữ liệu hay K) |
| 5 | `tb_smx_dv_reg` | IF-03, IF-07, IF-08 | 16 mẫu byteenable trên LEN, ROWS, SCALE_K và X_BUF ở mọi bank; địa chỉ không định nghĩa đọc 0, ghi bị bỏ qua, không alias; thanh ghi chỉ đọc và Y_BUF không ghi được; ghi X_BUF từng phần tử qua từng byte lane rồi so Y |
| 6 | `tb_smx_dv_random` | VER-01, FUN-05 | 60 run ngẫu nhiên theo `SEED`, chạy hai lượt với lịch sử khác nhau; ở lượt hai, cứ ba run thì một run bị reset bất đồng bộ giữa chừng (sau khi khởi động với SCALE_K sai) rồi chạy lại |

Chờ wrapper Avalon: ý "không X/Z khi `readdatavalid`" của VER-03 ở mức bus (luật R8 đã kiểm phần tương đương trên `acc_readdata`), và IF-01/02/11.

## Chạy

Từ thư mục gốc, một lần mỗi terminal: `source sim/setup.sh`. Sau đó trong `sim/`:

```bash
make dv                                    # compile, chạy cả 6 test ở P = 8, N_SEG = 8, in bảng kết quả
make dv P=4                                # tham số khác: P = 4, 8, 16 và N_SEG = 4, 8, 16
make build                                 # chỉ compile
make run testname=tb_smx_dv_proto          # chỉ chạy một test, không compile lại
make run testname=tb_smx_dv_random SEED=7  # seed khác: vector mới, log riêng
make run testname=tb_smx_dv_proto WAVE=1   # ghi wave/<run>.wlf
```

Test đạt khi log có `TB_RESULT: PASS`; `make dv` kết thúc bằng `DV ALL PASS`. Log ở `sim/log/`. Sau khi sửa `model/vec_dv_*.py` hoặc `dv_common.py`, chạy thêm `REGEN=1`.

## Mỗi run được kiểm những gì (`run_and_check`)

- Chu kỳ ngay sau START: BUSY = 1, DONE = 0, ERR = 0.
- DONE phải lên trong giới hạn REQ-PRF-03 (`R·(2·⌈L/P⌉ + 64) + 1` chu kỳ); quá thì báo lỗi và reset.
- Khi DONE lên: BUSY = 0, ERR = 0, `STATUS` đọc ra 2.
- `CYCLE_CNT` bằng số chu kỳ BUSY đếm được trên chân `status_busy`.
- Mọi phần tử `Y[r][i]`, `i < L`, khớp bit-exact với golden model.
- Suốt test, checker `dut.u_dv_chk` xét các luật R1–R8 (mô tả ở đầu `smx_core_chk.sv`); `finish` tính lỗi của checker vào kết quả.

## Đã kiểm đến đâu

- ModelSim Intel 10.5b: cả 6 test PASS ở P = N_SEG = 8, SEED = 1 (`make dv`, 2026-11-12), số phép so trùng với Verilator; `bind` và checker chạy được trên bản này. Các tổ hợp P, N_SEG khác chưa chạy trên ModelSim.
- Verilator 5.020 (2 trạng thái, không thấy X/Z): cả 6 test PASS ở P = 4/8/16 với N_SEG = 8 và N_SEG = 4/16 với P = 8.
- Cài lỗi thử trên bản sao RTL, P = N_SEG = 8, Verilator: 12/12 bị bắt (làm tròn `smx_norm`, đếm `CYCLE_CNT`, ghi LEN khi BUSY, ghi X_BUF khi BUSY, `cfg_ok` luôn đúng, mask lane đuôi, phép dịch `sum`, cờ `first` của `sum`, START khi BUSY, byteenable LEN, alias địa chỉ CSR, thiếu reset LEN).

## Lỗi tìm được

Không tự sửa `rtl/core/`, `model/softmax_ref.py` hay bản đồ thanh ghi. Ghi lại test, seed, tham số, dòng `ERROR` rồi báo người thiết kế RTL.
