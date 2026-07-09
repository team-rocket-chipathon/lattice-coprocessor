// SPDX-License-Identifier: MIT
// cocotb toplevel for spi_subordinate (Verilator). Drives the SPI master side and
// a mocked keccak core (via top-level signals wired into keccak_if) from Python.
//
// NOTE: uses SV interfaces -> Verilator only, not Icarus.

`default_nettype none
`timescale 1ns / 1ps

module tb ();
    localparam int unsigned RESULT_W = 512;
    localparam int unsigned HEALTH_W = 8;

    logic clk;
    logic rst_n;

    // --- SPI master-side stimulus (plain top-level signals for cocotb) ---
    logic sclk, mosi, ncs;
    wire  miso;
    spi_if spi ();
    assign spi.sclk = sclk;
    assign spi.cs_n = ncs;
    assign spi.mosi = mosi;
    assign miso     = spi.miso;

    // --- mocked keccak core (Python drives result/valid/mode, reads ready) ---
    logic [RESULT_W-1:0] kc_result;
    logic                kc_valid;
    logic [2:0]          kc_mode;
    wire                 kc_ready;
    keccak_if #(.MAX_R(512), .MAX_D(RESULT_W)) kc (.clk(clk));
    assign kc.result = kc_result;
    assign kc.valid  = kc_valid;
    assign kc.mode   = fips202::mode_t'(kc_mode);
    assign kc_ready  = kc.ready;

    // --- health monitor ---
    logic [HEALTH_W-1:0] health_status;
    logic                alarm;

    spi_subordinate #(.RESULT_W(RESULT_W), .HEALTH_W(HEALTH_W)) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .spi           (spi),
        .kc            (kc),
        .health_status (health_status),
        .alarm         (alarm)
    );

endmodule
