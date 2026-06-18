import fips202::mode_t;

module keccak_core (keccak_if.core keccak);

    logic    [1599:0] x, y, q;
    logic       [4:0] round;
    logic [23:0][6:0] iota_consts = {
        7'b0010111,
        7'b1000010,
        7'b0001101,
        7'b1001111,
        7'b0110011,
        7'b0110100,
        7'b0001001,
        7'b0100101,
        7'b1100101,
        7'b1011101,
        7'b1111001,
        7'b1111110,
        7'b0110010,
        7'b1010110,
        7'b0011000,
        7'b0111000,
        7'b1010101,
        7'b1001111,
        7'b1000010,
        7'b1111100,
        7'b0000111,
        7'b0111101,
        7'b0101100,
        7'b1000000
    };

    // Assign x and read q based on fips202 mode
    always_comb begin : select_mode
        case (keccak.mode)
            SHAKE128: // TODO: XOR x with message, assign results
            SHAKE256:
            SHA3_224:
            SHA3_256:
            SHA3_384:
            SHA3_512:
        endcase
    end

    // TODO: Round counter
    // Controls which iota const is applied
    // Asserts valid bit at the end of round 24

    keccak_round (.x, .y, .rc(iota_consts[round]))

    // TODO: DFF to store each round's results

endmodule
