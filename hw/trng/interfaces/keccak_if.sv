// Interfaces for the keccak_core module

import fips202::mode_t;

interface keccak_if #(
    parameter MAX_R = 1344, // Maximum rate (1344 to support all FIPS202 modes)
    parameter MAX_D = 512   // Maximum digest length (512 to support all FIPS202 modes)
) (
    input clk
);
    localparam int unsigned MESSAGE_BYTES = MAX_R / 8;
    initial begin: assert_MAX_R_byte_aligned
        assert (MAX_R % 8 == 0) else $error("keccak_if: MAX_R (%0d) must be byte-aligned", MAX_R);
    end

    fips202::mode_t                     mode;           // FIPS202 mode (SHAKE128, SHA3-256, etc.)
    logic                               enable;
    logic                               reset;
    logic                   [MAX_R-1:0] message_chunk;  // Raw message data
    logic [$clog2(MESSAGE_BYTES+1)-1:0] message_len;    // How many message bytes are valid (for padding)
    logic                   [MAX_D-1:0] result;         // Keccak output

    modport source ( // entropy source supplies bits and lets us know how long the message is
        input clk,
        output message_chunk,
        output message_len
    );

    modport monitor ( // health monitor observes keccak output and manages control signals
        input clk,
        output mode,
        output enable,
        output reset,
        input result
    );

    modport core (
        input clk,
        input mode,
        input enable,
        input reset,
        input message_chunk,
        input message_len,
        output result
    );

endinterface
