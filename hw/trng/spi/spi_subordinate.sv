// SPDX-License-Identifier: MIT
//
// SPI subordinate controller for the TRNG (Issue #11).
//
// Register-mapped SPI mode-0 subordinate. Reads the keccak core's output over the
// `keccak_if.consumer` modport and streams it to an off-chip host, and reports
// health-monitor status. Frame format / register map in docs/spi_interface.md.
//
//   16-bit frame, MSB first:  [15]=RW  [14:8]=addr[6:0]  [7:0]=data
//
// Keccak read path (per keccak_if): the SPI drives `ready`; when the core asserts
// `valid` for a SHAKE result it snapshots the whole result and streams it out
// byte-by-byte over SPI. It captures ONLY SHAKE-mode results — never the SHA-3
// conditioned seed, which must not leave the chip. Control of the keccak core
// (enable/mode/reset) belongs to the health monitor, not the SPI.
//
// NOTE: uses SV interface ports -> build/sim with Verilator, not Icarus.

`default_nettype none

module spi_subordinate #(
    parameter int unsigned FRAME_BITS = 16,
    parameter logic [7:0]  DEVICE_ID  = 8'h5A,
    parameter int unsigned RESULT_W   = 512,  // must match keccak_if MAX_D
    parameter int unsigned HEALTH_W   = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    spi_if.subordinate spi,        // external SPI wires (sclk/cs_n/mosi/miso)
    keccak_if.consumer kc,         // keccak output: read result/valid/mode, drive ready

    // Status plane: health monitor
    input  wire [HEALTH_W-1:0] health_status,
    input  wire                alarm
);

    localparam int unsigned RESULT_BYTES = RESULT_W / 8;
    localparam int unsigned PTR_W        = $clog2(RESULT_BYTES);
    localparam logic [PTR_W-1:0] LAST_BYTE = PTR_W'(RESULT_BYTES - 1);
    localparam logic [PTR_W-1:0] PTR_ONE   = PTR_W'(1);

    // Register addresses (see docs/spi_interface.md)
    localparam logic [6:0] ADDR_RNG_DATA = 7'h00;  // read a byte of the SHAKE result
    localparam logic [6:0] ADDR_STATUS   = 7'h01;  // health status
    localparam logic [6:0] ADDR_ALARM    = 7'h02;  // {..., data_not_ready, alarm}
    localparam logic [6:0] ADDR_ID       = 7'h03;  // constant device ID

    // ---------------------------------------------------------------------
    // Input synchronizers (SPI lines are async; oversampled in the clk domain).
    // ---------------------------------------------------------------------
    reg ncs_sync1,  ncs_sync2;
    reg mosi_sync1, mosi_sync2;
    reg sclk_sync1, sclk_sync2, sclk_sync3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ncs_sync1  <= 1'b1;  ncs_sync2  <= 1'b1;
            mosi_sync1 <= 1'b0;  mosi_sync2 <= 1'b0;
            sclk_sync1 <= 1'b0;  sclk_sync2 <= 1'b0;  sclk_sync3 <= 1'b0;
        end else begin
            ncs_sync1  <= spi.cs_n;   ncs_sync2  <= ncs_sync1;
            mosi_sync1 <= spi.mosi;   mosi_sync2 <= mosi_sync1;
            sclk_sync1 <= spi.sclk;
            sclk_sync2 <= sclk_sync1; sclk_sync3 <= sclk_sync2;
        end
    end

    wire selected     = ~ncs_sync2;
    wire sclk_rising  =  sclk_sync2 & ~sclk_sync3;
    wire sclk_falling = ~sclk_sync2 &  sclk_sync3;
    wire ncs_rising   =  ncs_sync1  & ~ncs_sync2;   // end of transaction

    // ---------------------------------------------------------------------
    // Keccak result snapshot. We capture the full result the instant it is
    // valid, then stream it out at SPI pace. Only SHAKE-mode results are
    // captured; SHA-3 results (the conditioned seed) are ignored.
    // ---------------------------------------------------------------------
    reg [RESULT_W-1:0] snapshot;    // captured SHAKE result
    reg                snap_valid;  // 1 = holding a result the host hasn't fully read
    reg [PTR_W-1:0]    read_ptr;    // next byte index to hand out

    wire is_shake = (kc.mode == fips202::SHAKE128) || (kc.mode == fips202::SHAKE256);

    // Ready for a new result only when we aren't holding one. Deasserting ready
    // also pauses the core while the host drains the current snapshot.
    assign kc.ready = ~snap_valid;

    // Current snapshot byte (byte 0 = LSB). Zero when nothing is buffered.
    wire [7:0] rng_byte = snap_valid ? snapshot[{read_ptr, 3'b000} +: 8] : 8'h00;

    // ---------------------------------------------------------------------
    // Receive shift register + frame decode.
    // ---------------------------------------------------------------------
    reg [4:0]  bit_count;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [7:0]  rx_shift;     // command then data byte; data byte unused for reads
    /* verilator lint_on UNUSEDSIGNAL */
    reg [7:0]  tx_shift;     // MISO shifted out from here, MSB first
    reg        will_advance; // this frame is a RNG_DATA read -> advance ptr at end

    wire [7:0] next_cmd = {rx_shift[6:0], mosi_sync2};

    // Read-data mux (combinational): the byte returned for the addressed reg.
    logic [7:0] read_data;
    always_comb begin
        case (next_cmd[6:0])
            ADDR_RNG_DATA: read_data = rng_byte;
            ADDR_STATUS:   read_data = 8'(health_status);
            ADDR_ALARM:    read_data = {6'b0, ~snap_valid, alarm}; // bit1=data_not_ready, bit0=alarm
            ADDR_ID:       read_data = DEVICE_ID;
            default:       read_data = 8'h00;
        endcase
    end

    // MISO valid only while selected; drive 0 otherwise (tristate is a pad concern)
    assign spi.miso = selected ? tx_shift[7] : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snapshot     <= '0;
            snap_valid   <= 1'b0;
            read_ptr     <= '0;
            bit_count    <= 5'd0;
            rx_shift     <= 8'h00;
            tx_shift     <= 8'h00;
            will_advance <= 1'b0;
        end else begin
            // --- capture a SHAKE result when we can accept one ---
            if (kc.valid && ~snap_valid && is_shake) begin
                snapshot   <= kc.result;
                snap_valid <= 1'b1;
                read_ptr   <= '0;
            end

            // --- SPI frame receive ---
            if (!selected) begin
                bit_count    <= 5'd0;
                will_advance <= 1'b0;
            end else if (sclk_rising && bit_count < FRAME_BITS[4:0]) begin
                rx_shift  <= {rx_shift[6:0], mosi_sync2};
                bit_count <= bit_count + 5'd1;

                // command byte complete on this edge (count goes 7 -> 8)
                if (bit_count == 5'd7 && !next_cmd[7]) begin   // read command
                    tx_shift     <= read_data;
                    will_advance <= (next_cmd[6:0] == ADDR_RNG_DATA) & snap_valid;
                end
            end

            // --- MISO shift out (after the master has sampled the MSB) ---
            if (sclk_falling && bit_count >= 5'd9) begin
                tx_shift <= {tx_shift[6:0], 1'b0};
            end

            // --- end of frame: advance read pointer on a RNG_DATA read ---
            if (ncs_rising && bit_count == FRAME_BITS[4:0] && will_advance) begin
                if (read_ptr == LAST_BYTE) begin
                    read_ptr   <= '0;
                    snap_valid <= 1'b0;   // last byte read -> release, re-arm ready
                end else begin
                    read_ptr <= read_ptr + PTR_ONE;
                end
            end
        end
    end

endmodule

`default_nettype wire
