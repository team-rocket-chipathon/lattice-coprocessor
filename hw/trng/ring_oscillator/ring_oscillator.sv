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
