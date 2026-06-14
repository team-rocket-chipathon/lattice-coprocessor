# hw/trng/spi — SPI subordinate

RTL home for the register-mapped SPI controller (Issue #11). **SystemVerilog**,
**Verilator-based** flow.

| File | What |
|------|------|
| `spi_subordinate.sv` | SPI mode-0 subordinate. Takes the SPI wires as an `spi_if.subordinate` interface port, oversamples them in the `clk` domain, decodes 16-bit frames, reads/writes the TRNG register map. |

Interface contract and register map: [`../../../docs/spi_interface.md`](../../../docs/spi_interface.md).
The SPI wires bundle into the shared `spi_if` interface in [`../interfaces/`](../interfaces/).

> **Verilator only — not Icarus.** This block uses an SV `interface` on the module
> port. Icarus/iverilog cannot parse interface ports (verified), so the whole flow
> (sim + lint) is Verilator. For synthesis, yosys would need `sv2v` to flatten the
> interface first — out of scope for now.

**Status:** validated in simulation (cocotb + Verilator, 3/3 passing) — reads,
RNG_DATA read-to-consume, and control writes all check out. Keccak/health ports
are stubs until ratified with @infinitymdm and @rahulearn2019.

## Test (cocotb + Verilator)

```bash
source /home/esarkar/myenv/bin/activate        # cocotb lives in this venv
cd hw/trng/spi/test && make
```

> **Heads-up for this machine:** `DATADISK` is a FUSE mount with no exec bit, so a
> Verilator-compiled binary can't run from here. Build elsewhere:
> ```bash
> make SIM_BUILD=/tmp/spi_sim_build
> ```
> (On a normal ext4 checkout the default `make` just works.)

Covers: ID/STATUS/ALARM reads, RNG_DATA FIFO consume+pop, CTRL enable/mode +
reseed/soft-reset pulses. The keccak FIFO and health monitor are modelled in
`test/test.py`.

## Lint

```bash
verilator --lint-only -Wall --top-module spi_subordinate \
    ../interfaces/spi_if.sv spi_subordinate.sv
```
(May emit benign UNDRIVEN/UNUSED notes for the interface members when linted in
isolation — no master is connected. The authoritative check is `make`.)
