// SPDX-License-Identifier: MIT
//
// SPI subordinate controller for the TRNG (Issue #11).
//
// Register-mapped SPI mode-0 subordinate. The SPI lines are asynchronous to the
// system clock and are oversampled in the `clk` domain (no clock is derived from
// SCLK). Frame format and register map are specified in docs/spi_interface.md.
//
//   16-bit frame, MSB first:  [15]=RW  [14:8]=addr[6:0]  [7:0]=data
//     RW=1 write : master drives data on MOSI
//     RW=0 read  : subordinate returns the addressed byte on MISO (bits 7:0)
//
// STATUS: validated in simulation (cocotb + Verilator, 3/3). Adjust once the
// keccak and health interfaces are ratified by Marcus and Rahul.
//
// NOTE: this module takes the SPI wires as an `spi_if.subordinate` interface
// port. SV interface ports are NOT supported by Icarus/iverilog — build and
// simulate with Verilator only. (We deliberately chose interfaces over flat
// ports; iverilog cannot parse them, so it is no longer part of this flow.)

`default_nettype none

module spi_subordinate #(
    parameter int unsigned FRAME_BITS = 16,
    parameter logic [7:0]  DEVICE_ID  = 8'h5A,
    parameter int unsigned RNG_W      = 8,   // keccak data word width
    parameter int unsigned HEALTH_W   = 8    // health-status width
) (
    // Clock / reset (digital domain)
    input  wire        clk,
    input  wire        rst_n,

    // SPI wires as an interface bundle (asynchronous, from off-chip master).
    // Members: spi.clk (SCLK), spi.cs_n (active-low select), spi.mosi, spi.miso.
    spi_if.subordinate spi,

    // Data plane: random bytes from keccak FIFO (Marcus)
    input  wire [RNG_W-1:0]    rng_data,
    input  wire                rng_valid,
    output reg                 rng_pop,     // 1-clk pulse: advance FIFO after a read

    // Status plane: health monitor (Rahul)
    input  wire [HEALTH_W-1:0] health_status,
    input  wire                alarm,

    // Control plane: to keccak (Marcus)
    output wire        ctrl_enable,
    output wire        ctrl_mode,    // 0=SHA-3 conditioning, 1=SHAKE-128
    output reg         ctrl_reseed,  // 1-clk pulse
    output reg         ctrl_soft_rst // 1-clk pulse
);

    // Register addresses (see docs/spi_interface.md §4)
    localparam logic [6:0] ADDR_RNG_DATA = 7'h00;
    localparam logic [6:0] ADDR_STATUS   = 7'h01;
    localparam logic [6:0] ADDR_ALARM    = 7'h02;
    localparam logic [6:0] ADDR_ID        = 7'h03;
    localparam logic [6:0] ADDR_CTRL      = 7'h10;

    // ---------------------------------------------------------------------
    // Input synchronizers. SCLK gets a 3rd stage so sync2 vs sync3 gives a
    // one-clk edge pulse. (Same scheme as the onboarding spi_peripheral.)
    // ---------------------------------------------------------------------
    reg ncs_sync1,  ncs_sync2;
    reg mosi_sync1, mosi_sync2;
    reg sclk_sync1, sclk_sync2, sclk_sync3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ncs_sync1  <= 1'b1;  // nCS idles high
            ncs_sync2  <= 1'b1;
            mosi_sync1 <= 1'b0;
            mosi_sync2 <= 1'b0;
            sclk_sync1 <= 1'b0;
            sclk_sync2 <= 1'b0;
            sclk_sync3 <= 1'b0;
        end else begin
            ncs_sync1  <= spi.cs_n;
            ncs_sync2  <= ncs_sync1;
            mosi_sync1 <= spi.mosi;
            mosi_sync2 <= mosi_sync1;
            sclk_sync1 <= spi.clk;
            sclk_sync2 <= sclk_sync1;
            sclk_sync3 <= sclk_sync2;
        end
    end

    wire selected     = ~ncs_sync2;
    wire sclk_rising  =  sclk_sync2 & ~sclk_sync3;
    wire sclk_falling = ~sclk_sync2 &  sclk_sync3;
    wire ncs_rising   =  ncs_sync1  & ~ncs_sync2;   // end of transaction

    // ---------------------------------------------------------------------
    // Receive shift register + frame decode.
    // ---------------------------------------------------------------------
    reg [4:0]  bit_count;
    // 8-bit data field is captured, but the register map currently defines only a
    // subset (CTRL low bits); the rest are reserved -> tell verilator that's intentional.
    /* verilator lint_off UNUSEDSIGNAL */
    reg [7:0]  rx_shift;     // MOSI shifted in here, MSB first (command then data byte)
    /* verilator lint_on UNUSEDSIGNAL */
    reg [7:0]  tx_shift;     // MISO shifted out from here, MSB first
    reg [1:0]  ctrl_reg;     // {mode, enable}

    reg        cmd_rw;       // latched RW bit of current frame
    reg [6:0]  cmd_addr;     // latched address of current frame
    reg        will_pop;     // this frame is a valid RNG_DATA read -> pop at end

    // 8-bit command as it will look right after the 8th bit is shifted in
    wire [7:0] next_cmd = {rx_shift[6:0], mosi_sync2};

    // Read-data mux (combinational): the byte returned for the addressed reg.
    // SPI returns one byte per read, so RNG_W/HEALTH_W signals are resized to 8
    // bits: narrower -> zero-extended, wider -> low byte (multi-byte readout of
    // wider words is a future extension).
    logic [7:0] read_data;
    always_comb begin
        case (next_cmd[6:0])
            ADDR_RNG_DATA: read_data = 8'(rng_data);
            ADDR_STATUS:   read_data = 8'(health_status);
            ADDR_ALARM:    read_data = {6'b0, ~rng_valid, alarm};
            ADDR_ID:       read_data = DEVICE_ID;
            default:       read_data = 8'h00;
        endcase
    end

    assign ctrl_enable = ctrl_reg[0];
    assign ctrl_mode   = ctrl_reg[1];
    // MISO valid only while selected; drive 0 otherwise (tristate is a pad concern)
    assign spi.miso    = selected ? tx_shift[7] : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count     <= 5'd0;
            rx_shift      <= 8'h00;
            tx_shift      <= 8'h00;
            ctrl_reg      <= 2'b00;
            cmd_rw        <= 1'b0;
            cmd_addr      <= 7'h00;
            will_pop      <= 1'b0;
            rng_pop       <= 1'b0;
            ctrl_reseed   <= 1'b0;
            ctrl_soft_rst <= 1'b0;
        end else begin
            // pulses default low; overridden below on the commit cycle
            rng_pop       <= 1'b0;
            ctrl_reseed   <= 1'b0;
            ctrl_soft_rst <= 1'b0;

            if (!selected) begin
                // idle between frames
                bit_count <= 5'd0;
                will_pop  <= 1'b0;
            end else if (sclk_rising && bit_count < FRAME_BITS[4:0]) begin
                rx_shift  <= {rx_shift[6:0], mosi_sync2};
                bit_count <= bit_count + 5'd1;

                // command byte complete on this edge (count goes 7 -> 8)
                if (bit_count == 5'd7) begin
                    cmd_rw   <= next_cmd[7];
                    cmd_addr <= next_cmd[6:0];
                    if (!next_cmd[7]) begin                // read
                        tx_shift <= read_data;
                        will_pop <= (next_cmd[6:0] == ADDR_RNG_DATA) & rng_valid;
                    end
                end
            end

            // MISO: shift out after the master has sampled the MSB.
            // First data bit (MSB) is held through rising edge #9 (bit_count==8),
            // then advance one bit per falling edge for bits 9..15.
            if (sclk_falling && bit_count >= 5'd9) begin
                tx_shift <= {tx_shift[6:0], 1'b0};
            end

            // Commit at end of a complete frame.
            if (ncs_rising && bit_count == FRAME_BITS[4:0]) begin
                if (cmd_rw) begin                          // write
                    case (cmd_addr)
                        ADDR_CTRL: begin
                            ctrl_reg      <= rx_shift[1:0]; // {mode, enable}
                            ctrl_reseed   <= rx_shift[2];
                            ctrl_soft_rst <= rx_shift[3];
                        end
                        default: ; // read-only / unmapped: ignore
                    endcase
                end else begin                             // read
                    rng_pop <= will_pop;                   // advance FIFO once
                end
            end
        end
    end

endmodule

`default_nettype wire
