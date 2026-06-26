`timescale 1ns / 1ps

// ============================================================================================= //
// ring_osc_tb - Simple Testbench for the True Random Number Generator                           //
// ============================================================================================= //

module ring_osc_tb;

  // -----------------------------------------------------------------------------------------
  // Testbench Parameters (Generics)
  // -----------------------------------------------------------------------------------------
  parameter integer NUM_CELLS     = 3;    // number of ring-oscillator cells
  parameter integer NUM_INV_START = 5;    // number of inverters in first cell (must be odd)
  parameter integer NUM_RAW_BITS  = 64;   // number of XOR-ed raw bits per random sample byte

  // -----------------------------------------------------------------------------------------
  // Signal Generators / Interconnects
  // -----------------------------------------------------------------------------------------
  reg        clk_gen  = 1'b0;
  reg        rstn_gen = 1'b0;
  reg        en_gen   = 1'b0;

  wire       rnd_valid;
  wire [7:0] rnd_data;

  // -----------------------------------------------------------------------------------------
  // Clock Generator (100MHz / 20ns period -> toggles every 10ns)
  // -----------------------------------------------------------------------------------------
  always begin
    #10 clk_gen = ~clk_gen;
  end

  // -----------------------------------------------------------------------------------------
  // Stimulus Generation (Asynchronous Power-up Sequence)
  // -----------------------------------------------------------------------------------------
  initial begin
  $dumpfile("trng_waves.vcd");
  $dumpvars(0, ring_osc_tb);
    // Reset releases at 25ns
    #25;
    rstn_gen = 1'b1;

    // Module enable activates at 100ns
    #75;
    en_gen = 1'b1;

    // Optional: Let simulation run to collect a few random samples, then finish
    // Modify the time budget below depending on how many numbers you want to harvest
    #200000;
    $display("Simulation complete.");
    $finish;
  end

  // -----------------------------------------------------------------------------------------
  // Device Under Test (DUT) Instantiation
  // -----------------------------------------------------------------------------------------
  ring_osc #(
    .NUM_CELLS     (NUM_CELLS),
    .NUM_INV_START (NUM_INV_START),
    .NUM_RAW_BITS  (NUM_RAW_BITS),
    .SIM_MODE      (1)            // SIM_MODE = 1 activates FF-delays for the simulator environment
  ) uut (
    .clk_i    (clk_gen),
    .rstn_i   (rstn_gen),
    .enable_i (en_gen),
    .valid_o  (rnd_valid),
    .data_o   (rnd_data)
  );

  // -----------------------------------------------------------------------------------------
  // Console Output Monitor
  // -----------------------------------------------------------------------------------------
  always @(posedge clk_gen) begin
    if (rnd_valid == 1'b1) begin
      // Prints the clean integer value of the collected byte directly to stdout
      $display("%d", rnd_data);
    end
  end

endmodule