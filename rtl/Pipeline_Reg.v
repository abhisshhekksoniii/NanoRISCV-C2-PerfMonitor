`timescale 1ns / 1ps
module Pipeline_Reg (
    input clk,
    input reset,
    input flush,
    input [31:0] if_pc,
    input [31:0] if_instruction,
    output reg [31:0] ex_pc,
    output reg [31:0] ex_instruction,
    output reg ex_valid            // 1 = real instruction in EX, 0 = bubble (reset or flush)
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_pc <= 32'd0;
            ex_instruction <= 32'h00000013; // NOP instruction
            ex_valid <= 1'b0;
        end else if (flush) begin
            ex_pc <= 32'd0;
            ex_instruction <= 32'h00000013; // NOP instruction (synchronous flush)
            ex_valid <= 1'b0;
        end else begin
            ex_pc <= if_pc;
            ex_instruction <= if_instruction;
            ex_valid <= 1'b1;
        end
    end
endmodule
