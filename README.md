# smx — Integer-Only Softmax Accelerator for Transformer Attention

BTL môn Cấu trúc phần cứng cho giải thuật học máy (nhóm 6). Avalon-MM IP cho Cyclone V (DE10-Standard) tính softmax INT8 → UINT8 theo hàng.

- Bắt đầu: `docs/PROJECT.md`, rồi `docs/requirements.md`.
- Golden model: `python3 model/softmax_ref.py --selftest` (cần Python 3 + NumPy).
- Mô phỏng (ModelSim): `cd sim && make testname=tb_smx_exp2 N_SEG=8`, hoặc `make regress`; danh sách file ở `sim/rtl.f`, `sim/tb.f`, `sim/testcase.f`.
- Hướng dẫn cho Claude Code: `CLAUDE.md`.
