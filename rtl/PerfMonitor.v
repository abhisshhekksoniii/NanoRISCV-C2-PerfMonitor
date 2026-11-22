`timescale 1ns / 1ps
// Hardware performance monitor for NanoRISCV-C2.
// Counts clock cycles and core events; one counter is shown on `data` at a time.
module PerfMonitor (
    input         clk,
    input         reset,          // asynchronous reset (same as the core)
    input         enable,         // counters run only while enable = 1
    input         clear,          // synchronous clear of all counters and overflow flags
    // event inputs from the core (all taken from the EX stage)
    input         instr_valid,    // 1 = a real instruction is in EX (0 = bubble)
    input         is_branch,      // a BEQ is in EX
    input         branch_taken,   // the BEQ is taken (this also flushes the pipeline)
    input         is_load,        // LW in EX
    input         is_store,       // SW in EX
    // read-out
    input  [2:0]  sel,            // 0 cycles, 1 instructions, 2 branches, 3 taken, 4 loads, 5 stores, 6 overflow flags
    output reg [31:0] data,
    output        overflow        // sticky: 1 if any counter has wrapped around
);
    reg [31:0] cycle_cnt, instr_cnt, branch_cnt, taken_cnt, load_cnt, store_cnt;
    reg [5:0]  ovf;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_cnt <= 32'd0; instr_cnt <= 32'd0; branch_cnt <= 32'd0;
            taken_cnt <= 32'd0; load_cnt  <= 32'd0; store_cnt  <= 32'd0;
            ovf <= 6'd0;
        end else if (clear) begin
            cycle_cnt <= 32'd0; instr_cnt <= 32'd0; branch_cnt <= 32'd0;
            taken_cnt <= 32'd0; load_cnt  <= 32'd0; store_cnt  <= 32'd0;
            ovf <= 6'd0;
        end else if (enable) begin
            cycle_cnt <= cycle_cnt + 32'd1;
            if (cycle_cnt == 32'hFFFFFFFF) ovf[0] <= 1'b1;
            if (instr_valid) begin
                instr_cnt <= instr_cnt + 32'd1;
                if (instr_cnt == 32'hFFFFFFFF) ovf[1] <= 1'b1;
            end
            if (is_branch) begin
                branch_cnt <= branch_cnt + 32'd1;
                if (branch_cnt == 32'hFFFFFFFF) ovf[2] <= 1'b1;
            end
            if (branch_taken) begin
                taken_cnt <= taken_cnt + 32'd1;
                if (taken_cnt == 32'hFFFFFFFF) ovf[3] <= 1'b1;
            end
            if (is_load) begin
                load_cnt <= load_cnt + 32'd1;
                if (load_cnt == 32'hFFFFFFFF) ovf[4] <= 1'b1;
            end
            if (is_store) begin
                store_cnt <= store_cnt + 32'd1;
                if (store_cnt == 32'hFFFFFFFF) ovf[5] <= 1'b1;
            end
        end
    end

    assign overflow = |ovf;

    always @(*) begin
        case (sel)
            3'd0:    data = cycle_cnt;
            3'd1:    data = instr_cnt;
            3'd2:    data = branch_cnt;
            3'd3:    data = taken_cnt;
            3'd4:    data = load_cnt;
            3'd5:    data = store_cnt;
            3'd6:    data = {26'd0, ovf};
            default: data = 32'd0;
        endcase
    end
endmodule
