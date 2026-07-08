// ============================================================================================= //
// ring_osc - Top-level                                              //
// ============================================================================================= //

module ring_osc #(
  parameter integer NUM_CELLS     = 3,   // number of ring-oscillator cells, min 1
  parameter integer NUM_INV_START = 3,   // inverters in first cell (must be odd, min 3)
  parameter integer NUM_RAW_BITS  = 512, // raw bits accumulated per output word (power of 2)
  parameter integer SIM_MODE      = 0    // 1 = simulation mode (no true/physical random)
) (
  input  wire               clk_i,    // module clock
  input  wire               rstn_i,   // module reset, low-active, async, optional
  input  wire               enable_i, // module enable (high-active)
  output wire               valid_o,  // data_o is valid; pulses high for exactly one cycle
  output wire [NUM_RAW_BITS-1:0] data_o    // accumulated raw random bits
);

  // Counter width: enough bits to count NUM_RAW_BITS raw bits plus one overflow/done bit.
  localparam integer CNT_WIDTH = $clog2(NUM_RAW_BITS) + 1;


  // -----------------------------------------------------------------------------------------
  // Entropy cell interconnect
  // -----------------------------------------------------------------------------------------
  wire [NUM_CELLS-1:0] cell_en_in;   // per-cell enable inputs
  wire [NUM_CELLS-1:0] cell_en_out;  // per-cell enable-chain outputs
  wire [NUM_CELLS-1:0] cell_rnd;     // per-cell synchronised random bit outputs
  reg                  cell_sum;     // XOR of all cell outputs (one raw bit per cycle)

  // Sampling control
  reg                   sample_en;              // registered copy of enable_i
  reg  [NUM_RAW_BITS-1:0] sample_sreg;          // 512-bit raw accumulation shift register
  reg  [CNT_WIDTH-1:0]  sample_cnt;             // bit counter; MSB = done/valid


  // -----------------------------------------------------------------------------------------
  // Entropy Source: ring-oscillator cells
  // -----------------------------------------------------------------------------------------

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
// Raw-bit accumulator
// -----------------------------------------------------------------------------------------
  always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sample_en   <= 1'b0;
      sample_cnt  <= {CNT_WIDTH{1'b0}};
      sample_sreg <= {NUM_RAW_BITS{1'b0}};
    end else begin
      sample_en <= enable_i;

      if (!sample_en || sample_cnt[CNT_WIDTH-1]) begin
        // Reset: disabled by user, or just completed a 512-bit accumulation
        sample_cnt  <= {CNT_WIDTH{1'b0}};
        sample_sreg <= {NUM_RAW_BITS{1'b0}};
      end else begin
        // Shift cell_sum into MSB; previous bits move toward LSB.
        // After NUM_RAW_BITS shifts, bit [0] holds the first collected bit and
        // bit [NUM_RAW_BITS-1] holds the most recent — oldest-first ordering.
        sample_cnt  <= sample_cnt + 1'b1;
        sample_sreg <= {sample_sreg[NUM_RAW_BITS-2:0], cell_sum};
      end
    end
  end

  // Outputs
  assign data_o  = sample_sreg;
  assign valid_o = sample_cnt[CNT_WIDTH-1];

endmodule

