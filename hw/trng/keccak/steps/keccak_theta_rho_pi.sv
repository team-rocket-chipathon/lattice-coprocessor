`timescale 1 ns / 1 ps

// Copied (with permission) from https://github.com/infinitymdm/penguin

module keccak_theta_rho_pi #(
    parameter W = 64
) (
    input  logic [4:0][4:0][W-1:0] x,
    output logic [4:0][4:0][W-1:0] y
);

    localparam int rho_offsets [24:0] = { // These work for all SHA3/SHAKE variations
          0,   1, 190,  28,  91,
         36, 300,   6,  55, 276,
          3,  10, 171, 153, 231,
        105,  45,  15,  21, 136,
        210,  66, 253, 120,  78
    };

    logic [23:0][W-1:0] A, B; // Temp wires for flipping bytes
    logic  [4:0][W-1:0] C, D; // As defined in FIPS202 section 3.2.1

    generate
        for (genvar i = 0; i < 5; i++) begin: sheet_select

            // Theta prep: assign C, D
            assign C[i] = x[i][0] ^ x[i][1] ^ x[i][2] ^ x[i][3] ^ x[i][4];
            for (genvar l = 0; l < W/8; l++) begin: theta_byte_select
                // Perform word and sheet rotations while accounting for byte-endianness
                assign D[i][8*l+:8] = {C[(i+4)%5][8*l+:7], C[(i+4)%5][(8*(l+2)-1)%W]} ^ C[(i+1)%5][8*l+:8];
            end

            // Theta / Rho / Pi: compute theta results while performing rho rotate and pi permute
            for (genvar j = 0; j < 5; j++) begin: lane_select
                if (rho_offsets[i+5*j] == 0) begin: rotate_0
                    // Theta / Rho / Pi: compute theta result and permute
                    assign y[j][(2*i+3*j+4)%5] = x[i][j] ^ D[i];
                end else begin: rotate_by_rho_offset
                    // Theta: compute theta result then reverse byte endianness for rotation
                    for (genvar m = 0; m < W/8; m++) begin: rho_byte_flip_A
                        assign A[i+5*j][8*m+:8] = {<<1{x[i][j][8*m+:8] ^ D[i][8*m+:8]}};
                    end
                    // Rho: rotate left by specified offset
                    assign B[i+5*j] = {A[i+5*j][(rho_offsets[i+5*j]%W)-1:0], A[i+5*j][W-1:(rho_offsets[i+5*j]%W)]};
                    // Pi: restore endianness and permute
                    for (genvar n = 0; n < W/8; n++) begin: rho_byte_flip_B
                        assign y[j][(2*i+3*j+4)%5][8*n+:8] = {<<1{B[i+5*j][8*n+:8]}};
                    end
                end
            end
        end
    endgenerate

endmodule
