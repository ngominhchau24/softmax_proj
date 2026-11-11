# tb/dv — môi trường DV cho `smx_core`

Verification chính thức của nhóm DV, tách khỏi các testbench tự kiểm của người thiết kế (`tb/tb_smx_*.sv`). DUT là `smx_core`, chỉ lái qua cổng `acc_*` (REQ-IF-06). Simulator: ModelSim, nên không dùng UVM.

## Thành phần

| File | Vai trò |
|---|---|
| `smx_dv_pkg.sv` | Địa chỉ thanh ghi, giới hạn, hằng timing. Chép từ `docs/requirements.md`, cố ý **không** import `smx_pkg`: RTL lệch khỏi requirements thì test phải fail |
| `smx_acc_bfm.sv` | BFM cổng `acc_*`: `write`, `read`, `read_burst`, `idle`. Lệnh lái ở cạnh xuống, dữ liệu đọc về sau 2 chu kỳ |
| `smx_scoreboard.sv` | Đọc vector golden từng run, đếm phép so và lỗi, in dòng `TB_RESULT` |
| `smx_dv_env.sv` | Clock, reset, DUT, BFM, scoreboard và các trình tự dùng chung: `init`, `program_run`, `start_run`, `wait_done`, `check_y`, `run_and_check`, `finish` |
| `../../model/dv_common.py` | Ghi file vector; số học lấy từ `softmax_ref.softmax_row` |
| `../../model/vec_dv_<test>.py` | Chọn kích thích cho từng test |

Một testcase là một module top `tb/tb_smx_dv_<test>.sv` khai báo `P`, `N_SEG`, tạo `smx_dv_env env ()` rồi gọi task của nó. Thêm test mới: viết `tb/tb_smx_dv_<test>.sv`, thêm vào `scripts/testcase.f`, và nếu cần vector thì thêm `model/vec_dv_<test>.py` (`sim/Makefile` tự gọi).

## Danh sách test

| # | Test | REQ | Trạng thái |
|---|---|---|---|
| 1 | `tb_smx_dv_sanity` | Giá trị reset, HW_PARAM, đọc ghi thanh ghi, vài run cơ bản (VER-01, FUN-01) | Đã viết |
| 2 | `tb_smx_dv_ver02` | VER-01, VER-02 đầy đủ, FUN-01/02/03 | Chưa viết |
| 3 | `tb_smx_dv_proto` + `smx_core_bind.sv` | VER-03, FUN-04, IF-09 | Chưa viết |
| 4 | `tb_smx_dv_latency` | VER-04 theo công thức trong spec | Chưa viết |
| 5 | `tb_smx_dv_reg` | IF-03, IF-07, IF-08 | Chưa viết |
| 6 | `tb_smx_dv_random` + reset giữa chừng | VER-01, FUN-05 | Chưa viết |

Chờ wrapper Avalon: ý "không X/Z khi `readdatavalid`" của VER-03, và IF-01/02/11.

## Chạy

```bash
source scripts/setup.sh                               # một lần mỗi terminal: trỏ flow tới ModelSim
cd sim && make testname=tb_smx_dv_sanity              # P = 8, N_SEG = 8
cd sim && make regress testname=tb_smx_dv_sanity PS="4 8 16" N_SEGS="4 8 16"
```

Test đạt khi log có `TB_RESULT: PASS`. Sau khi sửa `model/vec_dv_*.py` hoặc `dv_common.py`, chạy thêm `REGEN=1`.

## Mỗi run được kiểm những gì (`run_and_check`)

- Chu kỳ ngay sau START: BUSY = 1, DONE = 0, ERR = 0.
- DONE phải lên trong giới hạn REQ-PRF-03 (`R·(2·⌈L/P⌉ + 64) + 1` chu kỳ); quá thì báo lỗi và reset.
- Khi DONE lên: BUSY = 0, ERR = 0, `STATUS` đọc ra 2.
- `CYCLE_CNT` bằng số chu kỳ BUSY đếm được trên chân `status_busy`.
- Mọi phần tử `Y[r][i]`, `i < L`, khớp bit-exact với golden model.
- Suốt test: không X/Z trên chân trạng thái, BUSY và DONE không cùng bằng 1.

## Lỗi tìm được

Không tự sửa `rtl/core/`, `model/softmax_ref.py` hay bản đồ thanh ghi. Ghi lại test, seed, tham số, dòng `ERROR` rồi báo người thiết kế RTL.
