`timescale 1ns/1ps
//=============================================================================
//  dmem.v : 数据存储器（64 KB = 4096 x 128 位）
//  - 读：一次返回整行（16 B）
//  - 写：32 位写 + 字节使能，通过 16 路字节写使能落在一个 128 位行内
//  单读端口 + 单写端口，可推断 BRAM
//
//  初始化约定同 imem.v：仿真清零 + $readmemh；综合默认无初值，
//  需要预置数据时由 flatten.py 在 __MEM_INIT_HOOK__ 处插入 initial 赋值。
//=============================================================================
module dmem #(
    parameter LINES     = 4096,
    parameter INIT_FILE = "dmem.hex",
    parameter INIT_EN   = 1
)(
    input  wire         clk,

    input  wire [31:0]  addr,
    input  wire [31:0]  wdata,
    input  wire [3:0]   be,
    input  wire         we,
    input  wire         re,

    output reg  [127:0] rdata,
    output reg          rvalid
);

    reg [127:0] mem [0:LINES-1];

`ifdef SIM_INIT
    integer i;
    initial begin
        for (i = 0; i < LINES; i = i + 1)
            mem[i] = 128'd0;
        if (INIT_EN)
            $readmemh(INIT_FILE, mem);
    end
`endif

    // __MEM_INIT_HOOK__

    // 把 4 位字节使能平移到 16 字节通道中的对应位置
    wire [127:0] wdata_rep = {4{wdata}};
    wire [15:0]  be16      = {12'd0, be} << {addr[3:2], 2'b00};
    wire [11:0]  line      = addr[15:4];

    integer j;
    always @(posedge clk) begin
        if (we) begin
            for (j = 0; j < 16; j = j + 1) begin
                if (be16[j])
                    mem[line][j*8 +: 8] <= wdata_rep[j*8 +: 8];
            end
        end
        if (re)
            rdata <= mem[line];
        rvalid <= re;
    end

endmodule
