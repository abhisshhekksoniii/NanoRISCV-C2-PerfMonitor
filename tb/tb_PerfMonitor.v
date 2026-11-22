`timescale 1ns / 1ps

module tb_PerfMonitor;
    reg clk, reset, enable, clear;
    reg instr_valid, is_branch, branch_taken, is_load, is_store;
    reg [2:0] sel;
    wire [31:0] data;
    wire overflow;

    integer test_id, errors, k;

    PerfMonitor dut (
        .clk(clk), .reset(reset), .enable(enable), .clear(clear),
        .instr_valid(instr_valid), .is_branch(is_branch), .branch_taken(branch_taken),
        .is_load(is_load), .is_store(is_store),
        .sel(sel), .data(data), .overflow(overflow)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task cyc(input en, input clr, input v, input b, input t, input l, input s);
        begin
            @(negedge clk);
            enable = en; clear = clr;
            instr_valid = v; is_branch = b; branch_taken = t; is_load = l; is_store = s;
            @(posedge clk); #1;
        end
    endtask

    task check(input [255:0] name, input [31:0] got, input [31:0] expected);
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL  test %0d  %0s: got %0d, expected %0d", test_id, name, got, expected);
            end else
                $display("PASS  test %0d  %0s = %0d", test_id, name, got);
        end
    endtask

    task check_all(input [31:0] c, input [31:0] i, input [31:0] b,
                   input [31:0] t, input [31:0] l, input [31:0] s);
        begin
            sel = 0; #1; check("cycles       ", data, c);
            sel = 1; #1; check("instructions  ", data, i);
            sel = 2; #1; check("branches      ", data, b);
            sel = 3; #1; check("taken         ", data, t);
            sel = 4; #1; check("loads         ", data, l);
            sel = 5; #1; check("stores        ", data, s);
        end
    endtask

    initial begin
        errors = 0; test_id = 0;
        reset = 1; enable = 0; clear = 0; sel = 0;
        instr_valid = 0; is_branch = 0; branch_taken = 0; is_load = 0; is_store = 0;

        // 1: reset
        test_id = 1;
        #35;
        check_all(0, 0, 0, 0, 0, 0);
        check("overflow      ", overflow, 0);
        @(negedge clk); reset = 0;

        // 2: events ignored while disabled
        test_id = 2;
        cyc(0,0, 1,1,1,1,1);
        cyc(0,0, 1,1,1,1,1);
        cyc(0,0, 1,1,1,1,1);
        check_all(0, 0, 0, 0, 0, 0);

        // 3: known event pattern
        test_id = 3;
        cyc(1,0, 0,0,0,0,0);
        cyc(1,0, 1,0,0,0,0);
        cyc(1,0, 1,0,0,0,0);
        cyc(1,0, 1,1,0,0,0);
        cyc(1,0, 1,1,1,0,0);
        cyc(1,0, 0,0,0,0,0);
        cyc(1,0, 1,0,0,1,0);
        cyc(1,0, 1,0,0,0,1);
        check_all(8, 6, 2, 1, 1, 1);

        // 4: idle cycles
        test_id = 4;
        for (k = 0; k < 10; k = k + 1) cyc(1,0, 0,0,0,0,0);
        check_all(18, 6, 2, 1, 1, 1);

        // 5: disable freezes counters
        test_id = 5;
        cyc(0,0, 1,1,1,1,1);
        cyc(0,0, 1,1,1,1,1);
        check_all(18, 6, 2, 1, 1, 1);

        // 6: clear overrides events
        test_id = 6;
        cyc(1,1, 1,1,1,1,1);
        check_all(0, 0, 0, 0, 0, 0);

        // 7: counting resumes after clear
        test_id = 7;
        cyc(1,0, 1,0,0,0,0);
        cyc(1,0, 1,1,1,0,0);
        check_all(2, 2, 1, 1, 0, 0);

        // 8: cycle counter overflow
        test_id = 8;
        dut.cycle_cnt = 32'hFFFFFFFE;
        cyc(1,0, 0,0,0,0,0);
        check("overflow before wrap", overflow, 0);
        cyc(1,0, 0,0,0,0,0);
        sel = 0; #1; check("cycles after wrap  ", data, 0);
        check("overflow after wrap ", overflow, 1);
        sel = 6; #1; check("overflow bits sel6 ", data, 1);
        cyc(1,0, 0,0,0,0,0);
        check("overflow stays set  ", overflow, 1);

        // 9: clear removes overflow flag
        test_id = 9;
        cyc(1,1, 0,0,0,0,0);
        check("overflow after clear", overflow, 0);

        // 10: sel = 7 and asynchronous reset
        test_id = 10;
        cyc(1,0, 1,1,1,1,1);
        sel = 7; #1; check("sel 7 reads zero   ", data, 0);
        @(negedge clk);
        enable = 0; instr_valid = 0; is_branch = 0; branch_taken = 0; is_load = 0; is_store = 0;
        reset = 1; #3; reset = 0;
        check_all(0, 0, 0, 0, 0, 0);
        check("overflow after reset", overflow, 0);

        #40;
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d CHECK(S) FAILED", errors);
        $finish;
    end
endmodule
