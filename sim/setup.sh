# setup.sh - point the sim/ flow at ModelSim. Source it once per terminal, do not execute it:
#
#   source sim/setup.sh                      (from the repo root)
#   source setup.sh                          (from sim/)
#
# It sets vlib, vmap, vlog and vsim, the variables sim/Makefile reads. ModelSim is taken from, in
# this order:
#   1. MODELSIM_DIR, the folder that holds vsim or vsim.exe, if you set it:
#        MODELSIM_DIR=/mnt/c/intelFPGA_lite/18.1/modelsim_ase/win32aloem source sim/setup.sh
#   2. vsim or vsim.exe already on PATH (under WSL the Windows PATH is visible)
#   3. the usual Intel install folders on drives C and D (WSL) or under /opt and $HOME (Linux)
# To make a choice permanent for your machine, add an "export MODELSIM_DIR=..." line to ~/.bashrc.

unset SMX_MODELSIM_INI SMX_MODELSIM_ROOT
_smx_dir="${MODELSIM_DIR:-}"
_smx_ok=0

if [ -n "$_smx_dir" ] && [ ! -e "$_smx_dir/vsim.exe" ] && [ ! -e "$_smx_dir/vsim" ]; then
  echo "setup.sh: no vsim or vsim.exe in MODELSIM_DIR=$_smx_dir"
  _smx_dir=""
fi

# 2. tools on PATH, called by bare name
if [ -z "$_smx_dir" ]; then
  if command -v vsim >/dev/null 2>&1; then
    unset vlib vmap vlog vsim                # Makefile defaults
    echo "setup.sh: using vsim on PATH: $(command -v vsim)"
    vsim -version
    _smx_ok=1
  elif command -v vsim.exe >/dev/null 2>&1; then
    _smx_dir="$(dirname "$(command -v vsim.exe)")"      # Windows ModelSim: handled as a folder below
  fi
fi

# 3. usual install folders
if [ "$_smx_ok" = 0 ] && [ -z "$_smx_dir" ]; then
  for _smx_d in \
      /mnt/[cd]/intelFPGA_lite/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA_pro/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA*/*/modelsim_ae/win32aloem \
      /opt/intelFPGA*/*/modelsim_ase/bin \
      "$HOME"/intelFPGA*/*/modelsim_ase/bin; do
    if [ -e "$_smx_d/vsim.exe" ] || [ -e "$_smx_d/vsim" ]; then
      _smx_dir="$_smx_d"
      break
    fi
  done
fi

# 1. and 3.: a specific folder
if [ "$_smx_ok" = 0 ] && [ -n "$_smx_dir" ]; then
  if [ -e "$_smx_dir/vsim.exe" ]; then
    # Windows ModelSim under WSL. Started from WSL the tools do not locate their own install
    # folder: vmap cannot copy the default modelsim.ini and $MODEL_TECH in it does not resolve.
    # So put the folder first on PATH, call the tools by bare name, and let sim/Makefile write a
    # modelsim.ini from this install's default one, with absolute Windows library paths.
    export PATH="$_smx_dir:$PATH"
    export vlib=vlib.exe vmap=vmap.exe vlog=vlog.exe vsim=vsim.exe
    _smx_root="$(cd "$_smx_dir/.." && pwd)"
    if [ ! -f "$_smx_root/modelsim.ini" ]; then
      echo "setup.sh: WARNING no modelsim.ini in $_smx_root; files there:"
      ls "$_smx_root" | head -20
    elif ! command -v wslpath >/dev/null 2>&1; then
      echo "setup.sh: WARNING wslpath not found, cannot write Windows paths into modelsim.ini"
    else
      export SMX_MODELSIM_INI="$_smx_root/modelsim.ini"
      export SMX_MODELSIM_ROOT="$(wslpath -m "$_smx_root")"
      echo "setup.sh: make build will write sim/modelsim.ini from $SMX_MODELSIM_INI"
      echo "setup.sh: library root $SMX_MODELSIM_ROOT"
    fi
  else
    export vlib="$_smx_dir/vlib" vmap="$_smx_dir/vmap" vlog="$_smx_dir/vlog" vsim="$_smx_dir/vsim"
  fi
  echo "setup.sh: ModelSim in $_smx_dir"
  "$vsim" -version
  echo "setup.sh: vlog = $(command -v "$vlog")"
  _smx_ok=1
fi

if [ "$_smx_ok" = 0 ]; then
  echo "setup.sh: ModelSim not found."
  echo "  Find the folder that holds vsim.exe in Windows Explorer, then run for example:"
  echo "  MODELSIM_DIR=/mnt/c/intelFPGA_lite/18.1/modelsim_ase/win32aloem source sim/setup.sh"
fi

command -v make >/dev/null 2>&1    || echo "setup.sh: make is missing:  sudo apt install -y make"
python3 -c "import numpy" 2>/dev/null || echo "setup.sh: python3 with numpy is missing:  sudo apt install -y python3-numpy"

unset _smx_dir _smx_d _smx_ext _smx_root _smx_ok
