import fips202::mode_t;

module keccak_core (keccak_if.core keccak);

    logic             enable;
    logic      [10:0] r;
    logic       [9:0] c, d;
    logic    [1343:0] message_aligned;
    logic    [1343:0] message_padded;
    logic    [1599:0] x, y, q;
    logic       [4:0] round;
    logic [23:0][6:0] iota_consts = {
        7'b0010111, 7'b1000010, 7'b0001101, 7'b1001111, 7'b0110011, 7'b0110100,
        7'b0001001, 7'b0100101, 7'b1100101, 7'b1011101, 7'b1111001, 7'b1111110,
        7'b0110010, 7'b1010110, 7'b0011000, 7'b0111000, 7'b1010101, 7'b1001111,
        7'b1000010, 7'b1111100, 7'b0000111, 7'b0111101, 7'b0101100, 7'b1000000
    };

    assign enable = keccak.enable & keccak.ready;

    always_comb begin: select_mode
        case (keccak.mode)
            SHAKE128: {r, c, d} = {10'd1344,  9'd256, 9'd128};
            SHAKE256: {r, c, d} = {10'd1088,  9'd512, 9'd256};
            SHA3_224: {r, c, d} = {10'd1152,  9'd448, 9'd224};
            SHA3_256: {r, c, d} = {10'd1088,  9'd512, 9'd256};
            SHA3_384: {r, c, d} = { 10'd832,  9'd768, 9'd384};
            SHA3_512: {r, c, d} = { 10'd576, 9'd1024, 9'd512};
            default:  {r, c, d} = { 10'd576, 9'd1024, 9'd512};
        endcase
    end

    // Padding
    // Shift valid message bytes left, then pad out to length r with the appropriate suffix.
    // Bytes below 1344-r are set to zero.
    // Result is stored in message_padded.
    always_comb begin: padding
        // TODO: iterate over message bytes (starting at message_len) and pad up to rate
    end
    assign x = {message_padded ^ q[1599:256], q[255:0]};

    // Round counter
    // - Controls which iota const is applied
    // - Asserts valid bit at the end of round 24
    always_ff @(posedge keccak.clk) begin: round_counter
        if (keccak.reset) begin: reset_round_count
            round <= 0;
            keccak.valid <= 0;
        end else if (enable) begin: increment_round
            if (round == 23) begin: round_complete
                round <= 0;
                keccak.valid <= 1;
            end else begin: round_continuing
                round <= round + 1;
                keccak.valid <= 0;
            end
        end
    end

    // Single instance of keccak round hardware reused each cycle
    keccak_round (.x, .y, .rc(iota_consts[round]))

    // State DFF to store each round's results
    dffre #(.width(1600)) state (
        .clk(keccak.clk),
        .reset(keccak.reset),
        .enable,
        .d(y),
        .q
    );

    assign results = q[1599-:d];

endmodule
