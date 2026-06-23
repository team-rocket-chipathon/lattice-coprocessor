import fips202::*;

module keccak_core (keccak_if.core keccak);

    logic             enable, xof;
    logic       [7:0] r_bytes;
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
            SHAKE128: {r_bytes, xof} = {8'd168, 1'b1};
            SHAKE256: {r_bytes, xof} = {8'd136, 1'b1};
            SHA3_224: {r_bytes, xof} = {8'd144, 1'b0};
            SHA3_256: {r_bytes, xof} = {8'd136, 1'b0};
            SHA3_384: {r_bytes, xof} = {8'd104, 1'b0};
            SHA3_512: {r_bytes, xof} = { 8'd72, 1'b0};
            default:  {r_bytes, xof} = {8'd136, 1'b0}; // SHA3-256
        endcase
    end

    // Padding
    // - Left-align message bytes
    // - Pad out to length r using multirate padding with the appropriate suffix
    // - Bytes beyond r_bytes are filled in with zeros
    always_comb begin: padding
        for (int i = 0; i < 168; i++) begin: iterate_over_all_bytes
            // Case 1: valid incoming message byte. Copy to message_padded.
            // NOTE: Cases where message_len > $bits(message_chunk)/8 are considered user error
            if (i < keccak.message_len) begin: copy_message_byte
                message_padded[1343-8*i-:8] = keccak.message_chunk[$bits(keccak.message_chunk)-1-8*i-:8];
            end

            // Case 2: index within rate, but beyond message_len. Apply padding.
            // NOTE: Cases where message_len > r_bytes are considered user error
            else if (i < r_bytes) begin: pad_message
                case ({i == keccak.message_len, i == r_bytes-1})
                    2'b00: message_padded[1343-8*i-:8] = 8'h00;
                    2'b01: message_padded[1343-8*i-:8] = 8'h80;
                    2'b10: message_padded[1343-8*i-:8] = xof ? 8'h1f : 8'h06;
                    2'b11: message_padded[1343-8*i-:8] = xof ? 8'h9F : 8'h86;
                endcase
            end

            // Case 3: index beyond rate. Fill zeros.
            else begin: fill_zeros
                message_padded[1343-8*i-:8] = 8'h00;
            end
        end
    end

    // XOR message into inputs
    assign x = {message_padded ^ q[1599-:1344], q[255:0]};

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
    keccak_round k_round (.x, .y, .rc(iota_consts[round]));

    // State DFF to store each round's results
    dffre #(.width(1600)) state (
        .clk(keccak.clk),
        .reset(keccak.reset),
        .enable,
        .d(y),
        .q
    );

    // Always assign 512 bytes, even if fewer are valid
    // It's up to the consumer of these bits to use the correct width
    assign keccak.result = q[1599-:512];

endmodule
