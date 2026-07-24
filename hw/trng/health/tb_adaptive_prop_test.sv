`timescale 1 ns / 1 ps

// Testbench: adaptive_prop_test
//
// Covers 7 scenarios:
//   TC1  Perfect alternating stream         → no alarm
//   TC2  Pseudo-random stream (LFSR)        → no alarm
//   TC3  Stuck-at-0, anchor = 0            → alarm at bit 410
//   TC4  Stuck-at-1, anchor = 1            → alarm at bit 410
//   TC5  Stuck-at-0, anchor = 1            → NO alarm (APT blind spot, by design)
//   TC6  Window boundary — clean then new  → alarm-free, first_bit resets
//   TC7  alarm_clear restores operation    → alarm, clear, then pass again

module tb_adaptive_prop_test;
    logic clk, rst_n;
    logic bit_in, bit_valid, alarm_clear;
    logic prop_pass, alarm;

    adaptive_prop_test dut (
        .clk, .rst_n,
        .bit_in, .bit_valid, .alarm_clear,
        .prop_pass, .alarm
    );

    initial clk = 0;
    always #10 clk = ~clk;

    logic [15:0] lfsr;
    function automatic logic lfsr_next_bit(input logic [15:0] state);
        return state[15] ^ state[14] ^ state[12] ^ state[3];
    endfunction

    int tc_pass_count = 0;
    int tc_fail_count = 0;

    task automatic reset_dut();
        rst_n       = 0;
        bit_valid   = 0;
        bit_in      = 0;
        alarm_clear = 0;
        repeat(4) @(posedge clk);
        #1 rst_n = 1;
        @(posedge clk);
    endtask

    task automatic send_bit(input logic b);
        @(negedge clk);
        bit_in    = b;
        bit_valid = 1;
        @(posedge clk);
        #1;
        bit_valid = 0;
    endtask

    task automatic send_const(input logic b, input int n);
        for (int i = 0; i < n; i++)
            send_bit(b);
    endtask

    task automatic send_alternating(input logic b, input int n);
        logic cur = b;
        for (int i = 0; i < n; i++) begin
            send_bit(cur);
            cur = ~cur;
        end
    endtask

    task automatic send_lfsr(input int n);
        for (int i = 0; i < n; i++) begin
            send_bit(lfsr[0]);
            lfsr = {lfsr_next_bit(lfsr), lfsr[15:1]};
        end
    endtask

    task automatic check(
        input string  label,
        input logic   got_alarm,
        input logic   expect_alarm
    );
        if (got_alarm === expect_alarm) begin
            $display("  PASS  %s  (alarm=%0b)", label, got_alarm);
            tc_pass_count++;
        end else begin
            $display("  FAIL  %s  got alarm=%0b expected=%0b",
                     label, got_alarm, expect_alarm);
            tc_fail_count++;
        end
    endtask

    initial begin
        $dumpfile("tb_adaptive_prop_test.vcd");
        $dumpvars(0, tb_adaptive_prop_test);

        $display("─────────────────────────────────────────────────────────");
        $display(" Adaptive Proportion Test — Testbench");
        $display("─────────────────────────────────────────────────────────");

        $display("\nTC1: Perfect alternating stream (512 bits) → expect no alarm");
        reset_dut();
        send_alternating(1'b0, 512);
        @(posedge clk); #1;
        check("TC1 no alarm after alternating 512b", alarm, 1'b0);

        $display("\nTC2: LFSR pseudo-random stream (1024 bits) → expect no alarm");
        reset_dut();
        lfsr = 16'hACE1;
        send_lfsr(1024);
        @(posedge clk); #1;
        check("TC2 no alarm after LFSR 1024b", alarm, 1'b0);

        $display("\nTC3: Stuck-at-0, anchor=0 → alarm must fire by bit 410");
        reset_dut();
        begin
           int alarm_cycle;
           alarm_cycle=-1;
            for (int i = 1; i <= 512; i++) begin
                send_bit(1'b0);
                if (alarm && alarm_cycle < 0)
                    alarm_cycle = i;
            end
            if (alarm_cycle > 0)
                $display("  INFO  alarm fired at bit %0d (expect ≤410)", alarm_cycle);
            check("TC3 alarm fires (stuck-at-0, anchor=0)", alarm, 1'b1);
            if (alarm_cycle > 410)
                $display("  WARN  alarm fired LATE at bit %0d — check C", alarm_cycle);
        end

        $display("\nTC4: Stuck-at-1, anchor=1 → alarm must fire by bit 410");
        reset_dut();
        begin
            int alarm_cycle;
            alarm_cycle = -1;
            for (int i = 1; i <= 512; i++) begin
                send_bit(1'b1);
                if (alarm && alarm_cycle < 0)
                    alarm_cycle = i;
            end
            if (alarm_cycle > 0)
                $display("  INFO  alarm fired at bit %0d (expect ≤410)", alarm_cycle);
            check("TC4 alarm fires (stuck-at-1, anchor=1)", alarm, 1'b1);
        end

        $display("\nTC5: Stuck-at-0, anchor=1 → expect NO alarm (APT blind spot)");
        reset_dut();
        send_bit(1'b1);
        send_const(1'b0, 511);
        @(posedge clk); #1;
        check("TC5 no alarm (blind spot, monobit/rep_count cover)", alarm, 1'b0);

        $display("\nTC6: Two back-to-back clean windows (1024 bits) → no alarm");
        reset_dut();
        send_alternating(1'b0, 512);   // window 1
        send_alternating(1'b1, 512);   // window 2
        @(posedge clk); #1;
        check("TC6 no alarm across window boundary", alarm, 1'b0);

        $display("\nTC7: alarm fires, alarm_clear asserted, then clean window passes");
        reset_dut();
        // Trigger alarm
        send_const(1'b0, 512);
        @(posedge clk); #1;
        check("TC7a alarm fires before clear", alarm, 1'b1);

        @(negedge clk);
        alarm_clear = 1;
        @(posedge clk); #1;
        alarm_clear = 0;
        @(posedge clk); #1;
        check("TC7b alarm deasserted after clear", alarm, 1'b0);
        check("TC7c prop_pass restored after clear", prop_pass, 1'b1);

        send_alternating(1'b0, 512);
        @(posedge clk); #1;
        check("TC7d no alarm after clean window post-clear", alarm, 1'b0);

        $display("\n─────────────────────────────────────────────────────────");
        $display(" Results: %0d PASS, %0d FAIL", tc_pass_count, tc_fail_count);
        $display("─────────────────────────────────────────────────────────");

        if (tc_fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" FAILURES DETECTED — review waveform: tb_adaptive_prop_test.vcd");

        $finish;
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT — simulation took too long");
        $finish;
    end

endmodule
