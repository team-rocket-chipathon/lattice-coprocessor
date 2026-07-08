// Interfaces for the keccak_core module

import fips202::mode_t;

interface keccak_if #(
    parameter MAX_R = 512,  // Max input size. NOTE: MAX_R < 1344 implies all messages are 1 chunk
    parameter MAX_D = 512   // Max output size. (512 to support all FIPS202 modes)
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
    logic                               ready;          // Consumer can accept `result` this cycle
    logic                   [MAX_R-1:0] message_chunk;  // Raw message data
    logic [$clog2(MESSAGE_BYTES+1)-1:0] message_len;    // How many message bytes are valid (for padding)
    logic                   [MAX_D-1:0] result;         // Keccak output
    logic                               valid;          // Core has a result available

    modport source ( // entropy source supplies bits and lets us know how long the message is
        input clk,
        output message_chunk,   // For TRNG, only drive the lower 512 bits. The rest will be padded
        output message_len      // For TRNG, this can be fixed to 'd64 (indicating 512 bits)
    );

    modport monitor ( // health monitor observes keccak output and manages control signals
        input clk,
        output mode,    // Control whether operating in FIPS202 SHA3-512 or SHAKE-256 mode
        output enable,  // Assert when input message is ready at source modport
        output reset,   // Clear results & reset round count. Assert when changing mode
        input result,
        input valid     // Core asserts valid when round counter indicates completed hash / SHAKE
    );

    modport consumer ( // SPI controller can read results (but not manage controls)
        input clk,
        output ready,   // Halts the keccak core if deasserted. Transfer occurs on `valid && ready`
        input mode,     // Use mode to tell which bits of result are valid
        input result,
        input valid     // While `valid && !ready`, `result` must remain stable
    );

    modport core (
        input clk,
        input mode,
        input enable,
        input ready,
        input reset,
        input message_chunk,
        input message_len,
        output result,
        output valid
    );

endinterface
