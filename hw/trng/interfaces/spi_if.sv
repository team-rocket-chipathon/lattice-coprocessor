// SPDX-License-Identifier: MIT
//
// SPI interface for external communication. The chipathon design uses
// memory-mapped SPI to offload SHAKE-128 results and health-monitor status.
//
// Based on @infinitymdm's proposal (PR #2), with edits owned by the SPI block:
//   - `select` -> `cs_n`, documented ACTIVE-LOW (idles high), matching the SS pin.
//   - `clk` is the SPI serial clock (SCLK), driven by the main (so it is an
//     OUTPUT of the main modport), distinct from the core CLK pin.
//
// spi_subordinate takes this interface directly via the `subordinate` modport.
// Tooling: Icarus/iverilog does NOT support interface ports (verified), so the
// SPI block builds and simulates with **Verilator** (cocotb SIM=verilator). For
// synthesis, yosys would need sv2v to flatten this interface (out of scope now).

interface spi_if;
    logic clk;     // SPI serial clock (SCLK)
    logic cs_n;    // chip select, ACTIVE-LOW (idles high)
    logic mosi;    // main-out subordinate-in  (COPI)
    logic miso;    // main-in  subordinate-out (CIPO)

    modport main (
        output  clk,
        output  cs_n,
        output  mosi,
        input   miso
    );

    modport subordinate (
        input   clk,
        input   cs_n,
        input   mosi,
        output  miso
    );
endinterface
