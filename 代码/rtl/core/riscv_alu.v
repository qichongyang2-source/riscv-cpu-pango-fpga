`timescale 1ns/1ps
//=============================================================================
//  riscv_alu.v : 32 位算术逻辑单元
//=============================================================================
`include "riscv_defs.vh"

module riscv_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y
);

    always @(*) begin
        case (op)
            `ALU_ADD   : y = a + b;
            `ALU_SUB   : y = a - b;
            `ALU_SLL   : y = a << b[4:0];
            `ALU_SLT   : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            `ALU_SLTU  : y = (a < b) ? 32'd1 : 32'd0;
            `ALU_XOR   : y = a ^ b;
            `ALU_SRL   : y = a >> b[4:0];
            `ALU_SRA   : y = $signed(a) >>> b[4:0];
            `ALU_OR    : y = a | b;
            `ALU_AND   : y = a & b;
            `ALU_PASS_B: y = b;
            `ALU_PASS_A: y = a;
            default    : y = 32'd0;
        endcase
    end

endmodule
