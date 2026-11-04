`timescale 1ns/1ps
//=============================================================================
//  dcache.v : 数据 Cache（两路组相联 + 伪 LRU + 整行突发填充）
//    - 2 KB = 64 组 x 2 路 x 4 字（16 B/行），数据阵列按行存储
//    - 读命中：组合读 + 字选择，零等待
//    - 读缺失：128 位突发一次读回整行，3 拍完成
//    - 写策略：写穿 + 不写分配；写命中在行内做字节合并
//=============================================================================
module dcache #(
    parameter SETS = 64
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  addr,
    input  wire [31:0]  wdata,
    input  wire [3:0]   be,
    input  wire         we,
    input  wire         re,
    output wire [31:0]  rdata,
    output wire         hit,
    output wire         stall,

    output wire [31:0]  mem_addr,
    output wire         mem_re,
    output wire         mem_we,
    output wire [31:0]  mem_wdata,
    output wire [3:0]   mem_be,
    input  wire [127:0] mem_rdata,

    output reg  [31:0]  hit_cnt,
    output reg  [31:0]  miss_cnt
);

    localparam SET_W = 6;
    localparam TAG_W = 22;

    reg [127:0]      line [0:SETS*2-1];
    reg [TAG_W-1:0]  tag  [0:SETS*2-1];
    reg [SETS*2-1:0] valid;
    reg [SETS-1:0]   lru;

    wire [SET_W-1:0] set = addr[9:4];
    wire [1:0]       wr  = addr[3:2];
    wire [TAG_W-1:0] tg  = addr[31:10];

    wire [127:0] line0 = line[{set, 1'b0}];
    wire [127:0] line1 = line[{set, 1'b1}];

    wire w0_valid = valid[{set, 1'b0}];
    wire w1_valid = valid[{set, 1'b1}];
    wire w0_match = w0_valid && (tag[{set, 1'b0}] == tg);
    wire w1_match = w1_valid && (tag[{set, 1'b1}] == tg);

    assign hit   = w0_match | w1_match;
    assign rdata = w1_match ? line1[{wr, 5'b0} +: 32] : line0[{wr, 5'b0} +: 32];
    assign stall = re && !hit;

    wire hit_way = w1_match;
    wire victim  = !w0_valid ? 1'b0 : (!w1_valid ? 1'b1 : lru[set]);

    //------------------- 写命中的行内字节合并 -------------------------------
    wire [127:0] hit_line = hit_way ? line1 : line0;
    wire [31:0]  old_word = hit_line[{wr, 5'b0} +: 32];
    wire [31:0]  new_word = {
        be[3] ? wdata[31:24] : old_word[31:24],
        be[2] ? wdata[23:16] : old_word[23:16],
        be[1] ? wdata[15:8]  : old_word[15:8],
        be[0] ? wdata[7:0]   : old_word[7:0]
    };
    wire [127:0] sh_mask  = 128'h0000_0000_FFFF_FFFF << {wr, 5'b0};
    wire [127:0] sh_data  = {96'd0, new_word} << {wr, 5'b0};
    wire [127:0] line_upd = (hit_line & ~sh_mask) | sh_data;

    //------------------- 填充状态机 -----------------------------------------
    localparam S_IDLE = 2'd0;
    localparam S_CAP  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]        state;
    reg [SET_W-1:0]  f_set;
    reg [TAG_W-1:0]  f_tag;
    reg              f_way;

    wire filling = (state == S_IDLE) && re && !hit;

    assign mem_re    = filling;
    assign mem_we    = we && (state == S_IDLE);
    assign mem_addr  = (state == S_IDLE) ? (filling ? {addr[31:4], 4'b0000} : addr)
                                         : {f_tag, f_set, 4'b0000};
    assign mem_wdata = wdata;
    assign mem_be    = be;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            f_set    <= {SET_W{1'b0}};
            f_tag    <= {TAG_W{1'b0}};
            f_way    <= 1'b0;
            valid    <= {(SETS*2){1'b0}};
            lru      <= {SETS{1'b0}};
            hit_cnt  <= 32'd0;
            miss_cnt <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (we && hit)
                        line[{set, hit_way}] <= line_upd;

                    if (re && hit) begin
                        hit_cnt <= hit_cnt + 32'd1;
                        if (w1_match) lru[set] <= 1'b0;
                        else          lru[set] <= 1'b1;
                    end else if (re) begin
                        f_set  <= set;
                        f_tag  <= tg;
                        f_way  <= victim;
                        valid[{set, victim}] <= 1'b0;
                        state  <= S_CAP;
                        miss_cnt <= miss_cnt + 32'd1;
                    end
                end
                S_CAP: begin
                    line[{f_set, f_way}] <= mem_rdata;
                    tag[{f_set, f_way}]  <= f_tag;
                    valid[{f_set, f_way}]<= 1'b1;
                    lru[f_set]           <= ~f_way;
                    state                <= S_DONE;
                end
                S_DONE: begin
                    hit_cnt <= hit_cnt + 32'd1;
                    state   <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
