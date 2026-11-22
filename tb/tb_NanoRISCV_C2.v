`timescale 1ns / 1ps
module tb_NanoRISCV_C2;
    reg clk, reset, perf_enable, perf_clear;
    reg [2:0] perf_sel;
    wire [31:0] debug_out, perf_data;
    wire perf_overflow;
    integer i;
    reg [31:0] cycles, instrs, branches, taken, loads, stores;

    NanoRISCV_C2 uut (
        .clk(clk), .reset(reset),
        .perf_enable(perf_enable), .perf_clear(perf_clear), .perf_sel(perf_sel),
        .perf_data(perf_data), .perf_overflow(perf_overflow),
        .debug_out(debug_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;                       // 20 ns period = 50 MHz

    task read_counter(input [2:0] s, output [31:0] v);
        begin perf_sel = s; #1; v = perf_data; end
    endtask

    initial begin
        reset = 1; perf_enable = 0; perf_clear = 0; perf_sel = 0;
        #55 @(negedge clk);
        reset = 0; perf_enable = 1;              // start measuring

        wait (uut.pc_current == 32'h24);         // LW (address 0x1C) has finished in EX
        @(negedge clk);
        perf_enable = 0;                         // stop measuring

        read_counter(0, cycles);  read_counter(1, instrs);   read_counter(2, branches);
        read_counter(3, taken);   read_counter(4, loads);    read_counter(5, stores);

        $display("Cycles              = %0d", cycles);
        $display("Instructions        = %0d", instrs);
        $display("Branches (BEQ)      = %0d", branches);
        $display("Branches taken      = %0d", taken);
        $display("Loads / Stores      = %0d / %0d", loads, stores);
        $display("CPI x100            = %0d", (cycles * 100) / instrs);
        $display("Overflow flag       = %b", perf_overflow);
        $display("mem[0] = %0d (expected 15), x3 = %0d (expected 15)", uut.DataMem_Inst.memory[0], uut.RegFile_Inst.registers[3]);

        // test the clear input
        @(negedge clk); perf_clear = 1; @(negedge clk); perf_clear = 0;
        read_counter(0, cycles);
        $display("Cycles after clear  = %0d (expected 0)", cycles);
        $finish;
    end
endmodule
