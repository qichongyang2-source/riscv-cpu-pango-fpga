`timescale 1ns/1ps
//=============================================================================
//  icache.v : 指令 Cache（两路组相联 + 伪 LRU + 整行突发填充）
//    - 2 KB = 64 组 x 2 路 x 4 字（16 B/行）
//    - 数据阵列按"行"存储（128 位/项），整行一次写入 → 单写端口
//    - 命中：组合读 + 4 选 1 字选择，零等待
//    - 缺失：128 位突发一次读回整行，3 拍完成
//=============================================================================
module icache #(
    parameter SETS = 64
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  addr,
    output wire [31:0]  rdata,
    output wire         hit,
    output wire         stall,

    output wire [31:0]  mem_addr,
    output wire         mem_re,
    input  wire [127:0] mem_rdata,

    output reg  [31:0]  hit_cnt,
    output reg  [31:0]  miss_cnt
);

    localparam SET_W = 6;
    localparam TAG_W = 22;            // addr[31:10]

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
    assign stall = !hit;

    wire victim = !w0_valid ? 1'b0 : (!w1_valid ? 1'b1 : lru[set]);

    //------------------- 填充状态机 -----------------------------------------
    localparam S_IDLE = 2'd0;
    localparam S_CAP  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]        state;
    reg [SET_W-1:0]  f_set;
    reg [TAG_W-1:0]  f_tag;
    reg              f_way;

    wire filling = (state == S_IDLE) && !hit;

    assign mem_re   = filling;
    assign mem_addr = {addr[31:4], 4'b0000};

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
                    if (hit) begin
                        hit_cnt <= hit_cnt + 32'd1;
                        if (w1_match) lru[set] <= 1'b0;
                        else          lru[set] <= 1'b1;
                    end else begin
                        f_set  <= set;
                        f_tag  <= tg;
                        f_way  <= victim;
                        valid[{set, victim}] <= 1'b0;
                        state  <= S_CAP;
                        miss_cnt <= miss_cnt + 32'd1;
                    end
                end
                S_CAP: begin
                    line[{f_set, f_way}] <= mem_rdata;   // 整行一次写入
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
