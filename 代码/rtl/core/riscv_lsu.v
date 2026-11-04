`timescale 1ns/1ps
//=============================================================================
//  riscv_lsu.v : 访存单元
//  - 把字地址 + funct3 转换成字节使能 / 写数据
//  - 把读回的字数据按 funct3 做字节/半字提取与符号扩展
//  说明: 本设计在硬件上支持非对齐访问（由字节通路完成），不产生
//        load/store misaligned 异常。
//=============================================================================
module riscv_lsu (
    input  wire [1:0]  addr_lo,      // 字节地址低 2 位
    input  wire [2:0]  funct3,
    input  wire [31:0] store_data,   // 已转发后的 rs2
    input  wire [31:0] rdata,        // 存储器读回字

    output reg  [3:0]  be,           // 字节写使能
    output reg  [31:0] wdata,        // 写数据（重复铺满各字节通道）
    output reg  [31:0] load_data     // 扩展后的读数据
);

    //--------------------------- 写通路 --------------------------------------
    always @(*) begin
        be    = 4'b0000;
        wdata = store_data;
        case (funct3)
            3'b000: begin // SB
                be    = 4'b0001 << addr_lo;
                wdata = {4{store_data[7:0]}};
            end
            3'b001: begin // SH
                be    = addr_lo[1] ? 4'b1100 : 4'b0011;
                wdata = {2{store_data[15:0]}};
            end
            3'b010: begin // SW
                be    = 4'b1111;
                wdata = store_data;
            end
            default: begin
                be    = 4'b0000;
                wdata = store_data;
            end
        endcase
    end

    //--------------------------- 读通路 --------------------------------------
    wire [7:0]  byte_sel  = rdata[{addr_lo, 3'b000} +: 8];
    wire [15:0] half_sel  = addr_lo[1] ? rdata[31:16] : rdata[15:0];

    always @(*) begin
        case (funct3)
            3'b000: load_data = {{24{byte_sel[7]}}, byte_sel};   // LB
            3'b001: load_data = {{16{half_sel[15]}}, half_sel};  // LH
            3'b010: load_data = rdata;                           // LW
            3'b100: load_data = {24'd0, byte_sel};               // LBU
            3'b101: load_data = {16'd0, half_sel};               // LHU
            default: load_data = rdata;
        endcase
    end

endmodule
