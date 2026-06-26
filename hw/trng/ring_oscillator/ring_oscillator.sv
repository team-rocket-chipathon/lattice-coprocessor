module ring_osc_cell #(
  parameter integer NUM_INV  = 3,  // number of inverters, must be odd, min 3
  parameter integer SIM_MODE = 0   // 1 = simulation mode (no true/physical random)
) (
  input  wire clk_i,   // clock
  input  wire rstn_i,  // reset, low-active, async, optional
  input  wire en_i,    // enable-chain input
  output wire en_o,    // enable-chain output
  output wire rnd_o    // random data (sync)
);

  // Enable shift register
  reg  [NUM_INV-1:0] sreg;

  // Ring oscillator signals
  //   latch[i] : level-sensitive latch output for inverter stage i
  //   inv_in[i]: combinatorial input to inverter i (= latch of previous stage, with wrap)
  //   inv_out[i]: output of inverter i
  reg  [NUM_INV-1:0] latch;
  wire [NUM_INV-1:0] inv_in;
  reg  [NUM_INV-1:0] inv_out;

  // Output synchronizer (two-stage)
  reg  [1:0] sync;

  // -----------------------------------------------------------------------------------------
  // Enable Shift-Register
  // Shifts en_i through NUM_INV stages so each latch is enabled one at a time,
  // preventing the synthesis tool from collapsing all inverters into one.
  // -----------------------------------------------------------------------------------------
  always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i)
      sreg <= {NUM_INV{1'b0}};
    else
      sreg <= {sreg[NUM_INV-2:0], en_i};
  end

  // Provide the last shift-register stage to the outer enable chain
  assign en_o = sreg[NUM_INV-1];

  // -----------------------------------------------------------------------------------------
  // Ring Oscillator
  // Inverter input of stage i is the latch output of the PREVIOUS stage (rotate right).
  // -----------------------------------------------------------------------------------------
  assign inv_in = {latch[0], latch[NUM_INV-1:1]};

  genvar i;
  generate
    for (i = 0; i < NUM_INV; i = i + 1) begin : ring_osc_gen

      // -----------------------------------------------------------------------
      // Level-sensitive latch with asynchronous clear and individual enable.
      // -----------------------------------------------------------------------
      always @(*) begin
        if (!en_i)
          latch[i] = 1'b0;          // asynchronous clear
        else if (sreg[i])
          latch[i] = inv_out[i];    // transparent: pass inverter output
        // else: latch closed – hold previous value (implicit latch inference)
      end

      // -----------------------------------------------------------------------
      // Inverter stage
      // Physical mode : pure combinatorial NOT gate (real propagation delay on FPGA/ASIC)
      // Simulation mode: FF-registered NOT gate (adds a clock cycle of "delay")
      // -----------------------------------------------------------------------
      if (SIM_MODE == 0) begin : inverter_phy
        always @(*) begin
          inv_out[i] = ~inv_in[i];
        end
      end else begin : inverter_sim
        always @(posedge clk_i or negedge rstn_i) begin
          if (!rstn_i)
            inv_out[i] <= 1'b0;
          else
            inv_out[i] <= ~inv_in[i];
        end
      end

    end
  endgenerate

  // -----------------------------------------------------------------------------------------
  // Output Synchronizer
  // Two-stage synchronizer moves the free-running latch output into the clocked domain.
  // -----------------------------------------------------------------------------------------
  always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i)
      sync <= 2'b00;
    else
      sync <= {sync[0], latch[NUM_INV-1]};
  end

  assign rnd_o = sync[1];

endmodule


// ============================================================================================= //
// ring_osc - Top-level                                              //
// ============================================================================================= //

module ring_osc #(
  parameter integer NUM_CELLS     = 3,    // number of ring-oscillator cells, min 1
  parameter integer NUM_INV_START = 3,    // number of inverters in first cell (must be odd)
  parameter integer NUM_RAW_BITS  = 256,  // number of raw bits per random byte (must be power of 2)
  parameter integer SIM_MODE      = 0     // 1 = simulation mode (no true/physical random)
) (
  input  wire       clk_i,    // module clock
  input  wire       rstn_i,   // module reset, low-active, async, optional
  input  wire       enable_i, // module enable (high-active)
  output wire       valid_o,  // data_o is valid when high (pulses for exactly one cycle)
  output wire [7:0] data_o    // random data byte output
);

  // Counter width: enough bits to count NUM_RAW_BITS raw bits plus one overflow/done bit.
  localparam integer CNT_WIDTH = $clog2(NUM_RAW_BITS) + 1;

  // CRC-8 polynomial tap mask: x^8 + x^2 + x^1 + x^0
  localparam [7:0] POLY_C = 8'b0000_0111;

  // -----------------------------------------------------------------------------------------
  // Entropy cell interconnect
  // -----------------------------------------------------------------------------------------
  wire [NUM_CELLS-1:0] cell_en_out;  // per-cell enable-chain outputs
  wire [NUM_CELLS-1:0] cell_rnd;     // per-cell random bit outputs
  reg                  cell_sum;     // XOR of all cell outputs

  // Sampling control
  reg                  sample_en;              // registered copy of enable_i
  reg  [7:0]           sample_sreg;            // CRC-style accumulation shift register
  reg  [CNT_WIDTH-1:0] sample_cnt;             // raw-bit counter; MSB = done/valid

  // De-biasing (John von Neumann extractor)
  reg  [1:0]           debias_sreg;            // two-bit sample buffer
  reg                  debias_state;           // toggles to process every second cycle
  wire                 debias_valid;           // strobes when a de-biased bit is ready
  wire                 debias_data;            // the de-biased bit value

  // -----------------------------------------------------------------------------------------
  // Entropy Source: ring-oscillator cells
  // -----------------------------------------------------------------------------------------
  wire [NUM_CELLS-1:0] cell_en_in;   // per-cell enable inputs

  genvar c;
  generate
    // Wire up enable chain safely without dangerous bit slicing boundaries
    assign cell_en_in[0] = sample_en;
    for (c = 1; c < NUM_CELLS; c = c + 1) begin : en_chain_gen
      assign cell_en_in[c] = cell_en_out[c-1];
    end

    for (c = 0; c < NUM_CELLS; c = c + 1) begin : entropy_cell_gen
      ring_osc_cell #(
        .NUM_INV  (NUM_INV_START + 2*c),
        .SIM_MODE (SIM_MODE)
      ) ring_osc_cell_inst (
        .clk_i  (clk_i),
        .rstn_i (rstn_i),
        .en_i   (cell_en_in[c]),
        .en_o   (cell_en_out[c]),
        .rnd_o  (cell_rnd[c])
      );
    end
  endgenerate

  // XOR-combine all cell random outputs into a single bit
  integer k;
  always @(*) begin
    cell_sum = 1'b0;
    for (k = 0; k < NUM_CELLS; k = k + 1)
      cell_sum = cell_sum ^ cell_rnd[k];
  end

  // -----------------------------------------------------------------------------------------
  // John von Neumann Randomness Extractor (De-Biasing)
  // -----------------------------------------------------------------------------------------
  always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      debias_sreg  <= 2'b00;
      debias_state <= 1'b0;
    end else begin
      // Shift in the latest combined random bit (MSB first)
      debias_sreg  <= {debias_sreg[0], cell_sum};
      // Toggle active only when the last cell in the chain is enabled
      debias_state <= cell_en_out[NUM_CELLS-1] ? ~debias_state : 1'b0;
    end
  end

  // Valid when processing an odd cycle (debias_state=1) AND the two bits differ
  assign debias_valid = debias_state & (debias_sreg[1] ^ debias_sreg[0]);
  assign debias_data  = debias_sreg[0];

  // -----------------------------------------------------------------------------------------
  // Sampling Control
  // Accumulates NUM_RAW_BITS de-biased bits through a CRC-8 shift register.
  // -----------------------------------------------------------------------------------------
  always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sample_en   <= 1'b0;
      sample_cnt  <= {CNT_WIDTH{1'b0}};
      sample_sreg <= 8'h00;
    end else begin
      sample_en <= enable_i;

      if (!sample_en || sample_cnt[CNT_WIDTH-1]) begin
        // Reset at start-up, after disable, or once a full sample has been captured
        sample_cnt  <= {CNT_WIDTH{1'b0}};
        sample_sreg <= 8'h00;
      end else if (debias_valid) begin
        sample_cnt <= sample_cnt + 1'b1;
        // CRC-8 style mixing
        if (sample_sreg[7] ^ debias_data)
          sample_sreg <= {sample_sreg[6:0], 1'b0} ^ POLY_C;
        else
          sample_sreg <= {sample_sreg[6:0], 1'b0};
      end
    end
  end

  // Outputs
  assign data_o  = sample_sreg;
  assign valid_o = sample_cnt[CNT_WIDTH-1];

endmodule