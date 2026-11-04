`timescale 1ns/1ps
//=============================================================================
//  riscv_regfile.v : 32 x 32 位通用寄存器堆
//  - 两个组合读端口，一个同步写端口（写优先，x0 恒为 0）
//=============================================================================
module riscv_regfile (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

endmodule
