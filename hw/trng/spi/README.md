# hw/trng/spi - SPI subordinate

RTL for the register-mapped SPI controller (Issue #11). SystemVerilog,
Verilator-based flow.

Files:
```
  spi_subordinate.sv   SPI mode-0 subordinate. Reads the keccak result via the
                       keccak_if.consumer modport and streams it to an off-chip
                       host; reports health-monitor status.
  test/                cocotb + Verilator testbench.
```

Interface contract and register map: ../../../docs/spi_interface.md

## Build note

The module uses SystemVerilog interface ports (spi_if, keccak_if), so it builds
with Verilator, not Icarus.

## Test

```
source /home/esarkar/myenv/bin/activate
cd hw/trng/spi/test && make SIM_BUILD=/tmp/spi_int_build
```

Covers: SHAKE result readout, SHA-3 seed rejection, and status/alarm/ID reads.
