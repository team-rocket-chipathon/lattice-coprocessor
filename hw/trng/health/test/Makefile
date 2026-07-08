# cocotb + Verilator testbench for rct_monitor.
#
# Run with the cocotb venv active:
#   source /home/esarkar/myenv/bin/activate && make
# On the DATADISK FUSE mount (no exec bit), build elsewhere:
#   make SIM_BUILD=/tmp/rct_sim_build

SIM           ?= verilator
TOPLEVEL_LANG ?= verilog

RTL_DIR = $(PWD)/..

VERILOG_SOURCES += $(RTL_DIR)/rct_monitor.sv
VERILOG_SOURCES += $(PWD)/tb.sv

EXTRA_ARGS += --public-flat-rw
EXTRA_ARGS += --trace

TOPLEVEL = tb
MODULE   = test

include $(shell cocotb-config --makefiles)/Makefile.sim
