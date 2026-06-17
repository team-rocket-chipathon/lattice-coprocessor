`timescale 1 ns / 1 ps

// Copied (with permission) from https://github.com/infinitymdm/penguin

module keccak_chi #(
    parameter W = 64
) (
    input  logic [4:0][4:0][W-1:0] x,
    output logic [4:0][4:0][W-1:0] y
);

    generate
        for (genvar i = 0; i < 5; i++) begin: sheet_select
            for(genvar j = 0; j < 5; j++) begin: lane_select
                assign y[i][j] = x[i][j] ^ ((~x[(i+4)%5][j]) & x[(i+3)%5][j]);
            end
        end
    endgenerate

endmodule
