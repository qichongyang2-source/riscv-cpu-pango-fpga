`timescale 1ns/1ps
//=============================================================================
//  riscv_mul.v : 32x32 乘法单元
//    输入来自 EX/MEM 流水寄存器（已转发、已寄存），输出直接进 MEM/WB
//    这样乘法器不再位于 EX 级"转发 mux -> 乘法 -> 写回 mux"的长路径上
//    op: 3'd0 MUL, 3'd1 MULH, 3'd2 MULHSU, 3'd3 MULHU
//=============================================================================
module riscv_mul (
    input  wire [2:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);

    wire signed [63:0] a_s = {{32{a[31]}}, a};
    wire signed [63:0] b_s = {{32{b[31]}}, b};
    wire        [63:0] a_u = {32'd0, a};
    wire        [63:0] b_u = {32'd0, b};

    wire [63:0] prod_ss = a_s * b_s;
    wire [63:0] prod_su = a_s * $signed(b_u);   // 有符号 x 无符号
    wire [63:0] prod_uu = a_u * b_u;

    always @(*) begin
        case (op)
            3'd0:    result = prod_ss[31:0];     // MUL
            3'd1:    result = prod_ss[63:32];    // MULH
            3'd2:    result = prod_su[63:32];    // MULHSU
            3'd3:    result = prod_uu[63:32];    // MULHU
            default: result = 32'd0;
        endcase
    end

endmodule
