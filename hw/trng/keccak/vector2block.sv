`timescale 1 ns / 1 ps

// Copied (with permission) from https://github.com/infinitymdm/penguin

module vector2block #(
    parameter W = 64,
    parameter B = 25*W
) (
    input  logic [B-1:0]           vector,
    output logic [4:0][4:0][W-1:0] block
);

    generate
        for (genvar i = 0; i < 5; i++) begin: sheet_select
            for (genvar j = 0; j < 5; j++) begin: lane_select
                assign block[i][j] = vector[W*(i+5*j)+:W];
            end
        end
    endgenerate

endmodule
