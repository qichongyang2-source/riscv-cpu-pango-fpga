`timescale 1ns/1ps
//=============================================================================
//  riscv_btb.v : 分支目标缓冲 + 两位饱和计数器
//    - 64 项，index = pc[7:2]，tag = pc[31:8]
//    - 预测条件：表项有效 + tag 命中 + 计数器 >= 2
//    - 训练：实际跳转则写入目标并把计数器加 1；未跳转则计数器减 1
//=============================================================================
module riscv_btb #(
    parameter ENTRIES = 64,
    parameter IDX_W   = 6
)(
    input  wire        clk,
    input  wire        rst_n,

    //------------------- 查询（IF 级） ---------------------------------------
    input  wire [31:0] lookup_pc,
    output wire        pred_taken,
    output wire [31:0] pred_target,

    //------------------- 训练（EX 级） ---------------------------------------
    input  wire        upd_valid,
    input  wire [31:0] upd_pc,
    input  wire        upd_taken,
    input  wire [31:0] upd_target
);

    reg [23:0]        btb_tag [0:ENTRIES-1];
    reg [31:0]        btb_tgt [0:ENTRIES-1];
    reg [1:0]         bht     [0:ENTRIES-1];
    reg [ENTRIES-1:0] btb_vld;

    integer i;

    wire [IDX_W-1:0] lidx = lookup_pc[7:2];
    wire [23:0]      ltag = lookup_pc[31:8];

    assign pred_taken  = btb_vld[lidx] && (btb_tag[lidx] == ltag) && bht[lidx][1];
    assign pred_target = btb_tgt[lidx];

    wire [IDX_W-1:0] uidx = upd_pc[7:2];
    wire [23:0]      utag = upd_pc[31:8];

    always @(posedge clk) begin
        if (!rst_n) begin
            btb_vld <= {ENTRIES{1'b0}};
            for (i = 0; i < ENTRIES; i = i + 1)
                bht[i] <= 2'b00;
        end else if (upd_valid) begin
            if (upd_taken) begin
                btb_tag[uidx] <= utag;
                btb_tgt[uidx] <= upd_target;
                btb_vld[uidx] <= 1'b1;
                if (bht[uidx] != 2'd3)
                    bht[uidx] <= bht[uidx] + 2'd1;
            end else begin
                if (bht[uidx] != 2'd0)
                    bht[uidx] <= bht[uidx] - 2'd1;
            end
        end
    end

endmodule
