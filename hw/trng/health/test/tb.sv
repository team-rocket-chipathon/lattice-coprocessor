// SPDX-License-Identifier: MIT
// cocotb toplevel for rct_monitor (Verilator). WIDTH/CUTOFF here must match test.py.

`default_nettype none
`timescale 1ns / 1ps

module tb ();
    localparam int unsigned WIDTH  = 8;
    localparam int unsigned CUTOFF = 8;

    logic             clk;
    logic             rst_n;
    logic [WIDTH-1:0] sample;
    logic             sample_valid;
    wire              alarm;

    rct_monitor #(
        .WIDTH (WIDTH),
        .CUTOFF(CUTOFF)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample       (sample),
        .sample_valid (sample_valid),
        .alarm        (alarm)
    );

endmodule
