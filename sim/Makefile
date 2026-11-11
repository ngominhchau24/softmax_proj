# Simulation flow, run from sim/. Same organisation as risc_v milestone3/10_sim:
# The file lists live in ../scripts: compile.f = rtl.f + tb.f + testcase.f, with paths relative to sim/.
# testname is the top module to run. ../scripts/setup.sh points the flow at ModelSim.
#
#   make                                    clean, compile, run tb_smx_exp2 at P=8 N_SEG=8
#   make testname=tb_smx_exp2 N_SEG=16      same, for another test or parameter
#   make regress                            compile, run every PS x N_SEGS combination
#   make regress PS="4 8 16" N_SEGS=8       sweep P instead of N_SEG
#   make run WAVE=1                         run without recompiling, log wave/<run>.wlf
#   make dump                               compile, open the GUI with main_wave.do
#   make view                               compile, run with wave logging, open the .wlf
#   make clean
#
# A test passes only if its log contains "TB_RESULT: PASS".
# Every testbench declares parameters P and N_SEG and takes plusarg +VECDIR=<dir>.
# Every model/gen_vectors.py subcommand takes --p, --n-seg, --seed and --out.
# Run one job at a time per checkout: all of them share sim/work.
# The tools can be overridden from the environment, e.g. export vlog=/path/to/vlog.exe

testname ?= tb_smx_exp2
P        ?= 8
N_SEG    ?= 8
PS       ?= 8
N_SEGS   ?= 4 8 16
WAVE     ?= 0
REGEN    ?= 0

vlib ?= vlib
vmap ?= vmap
vlog ?= vlog
vsim ?= vsim

# model/softmax_ref.py needs numpy
PYTHON ?= $(if $(wildcard $(HOME)/venvs/ml/bin/python),$(HOME)/venvs/ml/bin/python,python3)

TESTNAME := $(testname)
BLOCK    := $(patsubst tb_smx_%,%,$(TESTNAME))
VECDIR   := ../tb/vectors/smx_$(BLOCK)/p$(P)_n$(N_SEG)
RUN      := $(TESTNAME)_p$(P)_n$(N_SEG)
SIMARGS  := -gP=$(P) -gN_SEG=$(N_SEG) work.$(TESTNAME) +VECDIR=$(VECDIR)

# Logging every signal over 1.2M+ vectors makes a large .wlf, so plain runs log nothing
ifeq ($(WAVE),1)
  ACC     := -voptargs="+acc"
  LOG_CMD := log -r /*;
endif

.PHONY: all build vectors run regress dump view clean

all: clean build run

build:
	mkdir -p log
	mkdir -p wave
	$(vlib) work
	$(vmap) work work
	$(vlog) -f ../scripts/compile.f

# gen_vectors.py writes .done last, so an interrupted run is regenerated.
# Blocks without arithmetic have no model/vec_<block>.py and need no vectors.
vectors:
	@if [ "$(BLOCK)" = exp2 ] || [ -f ../model/vec_$(BLOCK).py ]; then \
	  if [ "$(REGEN)" = 1 ] || [ ! -f $(VECDIR)/.done ]; then \
	    $(PYTHON) ../model/gen_vectors.py $(BLOCK) --p $(P) --n-seg $(N_SEG) --out $(VECDIR); \
	  fi; \
	fi

run: vectors
	mkdir -p log
	mkdir -p wave
	$(vsim) -c -l log/$(RUN).log -wlf wave/$(RUN).wlf $(ACC) $(SIMARGS) -do "$(LOG_CMD) run -all; quit -f"
	ln -sf ./log/$(RUN).log sim.log
	@grep -q "TB_RESULT: PASS" log/$(RUN).log

regress: build
	@fail=0; for p in $(PS); do for n in $(N_SEGS); do \
	  $(MAKE) --no-print-directory run P=$$p N_SEG=$$n || fail=1; \
	done; done; \
	if [ $$fail = 0 ]; then echo "ALL PASS: $(TESTNAME) P = $(PS) N_SEG = $(N_SEGS)"; \
	else echo "SOME FAILED, see sim/log/"; exit 1; fi

dump: build vectors
	$(vsim) -gui -voptargs="+acc" $(SIMARGS) -do "do main_wave.do"

view: WAVE := 1
view: ACC := -voptargs="+acc"
view: LOG_CMD := log -r /*;
view: build run
	$(vsim) -view wave/$(RUN).wlf -do "do main_wave.do"

clean:
	@echo "Makefile cleaning"
	rm -rf work
	rm -rf wave
	rm -rf *ini
	rm -rf *log
	rm -rf *.wlf
	rm -rf transcript
