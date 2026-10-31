# smx — Integer-Only Softmax Accelerator for Transformer Attention

BTL môn Cấu trúc phần cứng cho giải thuật học máy (nhóm 6). Avalon-MM IP cho Cyclone V (DE10-Standard) tính softmax INT8 → UINT8 theo hàng.

- Bắt đầu: `docs/PROJECT.md`, rồi `docs/requirements.md`.
- Golden model: `python3 model/softmax_ref.py --selftest` (cần Python 3 + NumPy).
- Hướng dẫn cho Claude Code: `CLAUDE.md`.
