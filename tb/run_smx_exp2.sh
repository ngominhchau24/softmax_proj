#!/usr/bin/env bash
# run_smx_exp2.sh - generate vectors (if missing) and run tb_smx_exp2 in ModelSim
# for each requested N_SEG. Run from anywhere; paths are relative to the repo root.
#
# Usage: tb/run_smx_exp2.sh [N_SEG ...]        (default: 4 8 16)
#        REGEN=1 tb/run_smx_exp2.sh 8          (force regenerating vectors)
# Needs: python3 (+ numpy, for model/softmax_ref.py), vlib/vlog/vsim on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

segs=("$@")
[ ${#segs[@]} -eq 0 ] && segs=(4 8 16)

[ -d work ] || vlib work
vlog -sv rtl/pkg/smx_pkg.sv rtl/core/smx_exp2.sv tb/tb_smx_exp2.sv

fail=0
for n in "${segs[@]}"; do
  dir="tb/vectors/smx_exp2/n${n}"
  if [ "${REGEN:-0}" = 1 ] || [ ! -f "${dir}/t4.hex" ]; then
    python3 model/gen_vectors.py exp2 --n-seg "${n}" --out "${dir}"
  fi
  log="tb/vectors/smx_exp2/sim_n${n}.log"
  vsim -c -gN_SEG="${n}" tb_smx_exp2 +VECDIR="${dir}" -do "run -all; quit -f" | tee "${log}"
  grep -q "TB_RESULT: PASS" "${log}" || fail=1
done

if [ "${fail}" = 0 ]; then echo "ALL PASS: N_SEG = ${segs[*]}"; else echo "SOME FAILED, see tb/vectors/smx_exp2/sim_n*.log"; exit 1; fi
