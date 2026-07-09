# cocotb + Verilator testbench for spi_subordinate.
#
# We use Verilator (not Icarus) because spi_subordinate takes the SPI wires as a
# SystemVerilog `interface` port, which Icarus/iverilog cannot parse.
#
# Run with the cocotb virtualenv active:
#   source /home/esarkar/myenv/bin/activate && make
#
# See https://docs.cocotb.org/en/stable/quickstart.html

SIM           ?= verilator
TOPLEVEL_LANG ?= verilog

RTL_DIR     = $(PWD)/..
IF_DIR      = $(PWD)/../../interfaces
KECCAK_DIR  = $(PWD)/../../keccak

# Package + interfaces first, then the module that uses them, then the testbench.
VERILOG_SOURCES += $(KECCAK_DIR)/fips202.sv
VERILOG_SOURCES += $(IF_DIR)/keccak_if.sv
VERILOG_SOURCES += $(IF_DIR)/spi_if.sv
VERILOG_SOURCES += $(RTL_DIR)/spi_subordinate.sv
VERILOG_SOURCES += $(PWD)/tb.sv

# Expose internal tb signals to cocotb (tb has no ports) and allow waveform dump.
EXTRA_ARGS += --public-flat-rw
EXTRA_ARGS += --trace

TOPLEVEL = tb
MODULE   = test

include $(shell cocotb-config --makefiles)/Makefile.sim
