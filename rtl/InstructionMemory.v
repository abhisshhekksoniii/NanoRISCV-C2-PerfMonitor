`timescale 1ns / 1ps

module InstructionMemory (
    input wire [31:0] read_address,
    output wire [31:0] instruction
);
    reg [31:0] RAM [0:127];

    integer i;
    initial begin
        // Default every location to NOP (addi x0, x0, 0) to prevent X values
        for (i = 0; i < 128; i = i + 1) begin
            RAM[i] = 32'h00000013;
        end

        // Loop test program: sum = 5 + 4 + 3 + 2 + 1 = 15
        RAM[0] = 32'h00500093; // ADDI x1, x0, 5     (counter = 5)
        RAM[1] = 32'h00000113; // ADDI x2, x0, 0     (sum = 0)
        RAM[2] = 32'h00110133; // ADD  x2, x2, x1    (loop: sum += counter)
        RAM[3] = 32'hFFF08093; // ADDI x1, x1, -1    (counter--)
        RAM[4] = 32'h00008463; // BEQ  x1, x0, +8    (counter == 0 ? exit)
        RAM[5] = 32'hFE000AE3; // BEQ  x0, x0, -12   (always taken: back to loop)
        RAM[6] = 32'h00202023; // SW   x2, 0(x0)     (mem[0] = sum)
        RAM[7] = 32'h00002183; // LW   x3, 0(x0)     (x3 = 15)
    end

    // Asynchronous read, word aligned (7 address bits = 128 words)
    assign instruction = RAM[read_address[8:2]];
endmodule
