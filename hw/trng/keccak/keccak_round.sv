`timescale 1 ns / 1 ps

// Copied (with permission) from https://github.com/infinitymdm/penguin

module keccak_round #(
    parameter L = 6,
    parameter W = 2**L,
    parameter B = 25*W
) (
    input  logic [B-1:0] x,
    input  logic   [L:0] rc,
    output logic [B-1:0] y
);

    // keccak_round encapsulates a single step of the keccak transformation function.
    // Each step contains theta, rho, pi, chi, and iota subfunctions in sequence.
    // See FIPS202 section 3.2 for details.

    logic [4:0][4:0][W-1:0] x_block, x_pi, x_chi, y_block;

    // Reorganize i/o into 3-dimensional blocks for easy indexing in subfunctions
    // TODO: This could probably be replaced with a function that evaluates indices at elaboration
    vector2block #(.W, .B) v2b (.vector(x), .block(x_block));
    block2vector #(.W, .B) b2v (.block(y_block), .vector(y));

    // Perform a single round of the keccak-p permutation
    keccak_theta_rho_pi #(.W) thrhp (.x(x_block), .y(x_pi));
    keccak_chi          #(.W) chi   (.x(x_pi),    .y(x_chi));
    keccak_iota         #(.L) iota  (.x(x_chi),   .y(y_block), .rc);

endmodule
