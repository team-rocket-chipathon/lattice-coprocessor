// SPDX-License-Identifier: MIT
// cocotb toplevel (Verilator). Drives the SPI master side onto an spi_if bundle
// and connects it to the interface-based spi_subordinate. The keccak FIFO and
// health monitor are modelled in Python (test.py).
//
// NOTE: uses an SV interface -> Verilator only. This will NOT build under
// Icarus/iverilog, which cannot parse interface ports.

`default_nettype none
`timescale 1ns / 1ps

module tb ();

    // cocotb-driven, plain top-level signals (easy for cocotb to access)
    logic        clk;
    logic        rst_n;
    logic        sclk;       // SPI master clock stimulus
    logic        mosi;
    logic        ncs;        // active-low select stimulus
    wire         miso;       // sampled by cocotb

    // SPI wire bundle; master side driven from the stimulus above
    spi_if spi ();
    assign spi.sclk = sclk;
    assign spi.cs_n = ncs;
    assign spi.mosi = mosi;
    assign miso     = spi.miso;

    // keccak data plane (driven by the Python FIFO model)
    logic [7:0] rng_data;
    logic       rng_valid;
    wire        rng_pop;

    // health status plane
    logic [7:0] health_status;
    logic       alarm;

    // keccak control plane
    wire        ctrl_enable;
    wire        ctrl_mode;
    wire        ctrl_reseed;
    wire        ctrl_soft_rst;

    spi_subordinate dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .spi           (spi),
        .rng_data      (rng_data),
        .rng_valid     (rng_valid),
        .rng_pop       (rng_pop),
        .health_status (health_status),
        .alarm         (alarm),
        .ctrl_enable   (ctrl_enable),
        .ctrl_mode     (ctrl_mode),
        .ctrl_reseed   (ctrl_reseed),
        .ctrl_soft_rst (ctrl_soft_rst)
    );

endmodule
