// SPDX-License-Identifier: MIT
//
// NIST SP 800-90B Repetition Count Test (RCT) — Issue #8.
//
// Continuous health test for an entropy source: detects a "stuck" source by
// counting consecutive identical samples. If the same value repeats CUTOFF times
// in a row, the source has likely failed and `alarm` is raised (and latched
// until reset).
//
// Algorithm (SP 800-90B 4.4.1):
//   A = first sample;  B = 1
//   for each new sample X:
//     if X == A:  B++;  if B >= C:  FAIL
//     else:       A = X; B = 1
//
// CUTOFF (C) is a parameter: C = 1 + ceil(-log2(alpha) / H_min), where alpha is
// the acceptable false-alarm rate and H_min the per-sample min-entropy. Set it to
// match the entropy source. Must be >= 2.

`default_nettype none

module rct_monitor #(
    parameter int unsigned WIDTH  = 1,    // bits per entropy sample
    parameter int unsigned CUTOFF = 32    // repetition cutoff C (>= 2)
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [WIDTH-1:0]  sample,        // entropy sample
    input  logic              sample_valid,  // 1 = `sample` is new this cycle
    output logic              alarm          // 1 (latched) = run reached CUTOFF
);

    // Counter wide enough to hold CUTOFF.
    localparam int unsigned CW = $clog2(CUTOFF + 1);

    logic [WIDTH-1:0] prev;     // A: last sample seen
    logic [CW-1:0]    count;    // B: current run length
    logic             primed;   // has the first sample been latched?

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev   <= '0;
            count  <= '0;
            primed <= 1'b0;
            alarm  <= 1'b0;
        end else if (sample_valid) begin
            if (!primed) begin
                // first sample after reset: A = X, B = 1
                prev   <= sample;
                count  <= CW'(1);
                primed <= 1'b1;
            end else if (sample == prev) begin
                // repeat: B++ (saturating); fail when B reaches CUTOFF
                if (count < CW'(CUTOFF)) begin
                    count <= count + CW'(1);
                    if (count + CW'(1) >= CW'(CUTOFF))
                        alarm <= 1'b1;     // latched until reset
                end
            end else begin
                // streak broken: A = X, B = 1
                prev  <= sample;
                count <= CW'(1);
            end
        end
    end

endmodule

`default_nettype wire
