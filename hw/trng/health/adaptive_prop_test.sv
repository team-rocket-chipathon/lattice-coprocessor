`timescale 1 ns / 1 ps

// Adaptive Proportion Test (APT)
// Integration:
//   bit_in / bit_valid come from the Von Neumann / post-processing stage.
//   alarm is a level signal — stays asserted until alarm_clear from trng_ctrl.
//   keccak_enable should be gated with ~alarm externally in trng_top.

module adaptive_prop_test (
    input  logic clk,
    input  logic rst_n,

    input  logic bit_in,
    input  logic bit_valid,

    input  logic alarm_clear,

    // To trng_ctrl / oht_gate
    output logic prop_pass,
    output logic alarm
);
    localparam int unsigned W      = 512;
    localparam int unsigned C      = 410;
    localparam int unsigned W_BITS = $clog2(W + 1);
    localparam int unsigned B_BITS = $clog2(C + 1);

    // NIST SP (S → anchor, B → match_count) for readability.
    logic              S;      // first bit of the current window (NIST: S)
    logic [B_BITS-1:0] B; // number of bits matching anchor   (NIST: B)
    logic [W_BITS-1:0] pos;
    logic              first_bit;

    logic alarm_lat;
    logic alarm_comb;

    assign alarm_comb = (B >= C[B_BITS-1:0]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            alarm_lat <= 1'b0;
        else if (alarm_clear)
            alarm_lat <= 1'b0;
        else if (alarm_comb)
            alarm_lat <= 1'b1;
    end

    assign alarm     = alarm_lat | alarm_comb;
    assign prop_pass = ~alarm;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S         <= 1'b0;
            B         <= '0;
            pos       <= '0;
            first_bit <= 1'b1;
        end

        else if (alarm_clear) begin
            S         <= 1'b0;
            B         <= '0;
            pos       <= '0;
            first_bit <= 1'b1;
        end

        else if (bit_valid && !alarm_lat && !alarm_comb) begin

            if (first_bit) begin
                S         <= bit_in;
                B         <= {{(B_BITS-1){1'b0}}, 1'b1};  // B = 1
                pos       <= {{(W_BITS-1){1'b0}}, 1'b1};  // pos = 1
                first_bit <= 1'b0;

            end else begin
                if (bit_in == S)
                    B <= B + 1'b1;

                pos <= pos + 1'b1;

                if (pos == W_BITS'(W-1)) begin
                    first_bit <= 1'b1;
                end
            end
        end
    end

endmodule
