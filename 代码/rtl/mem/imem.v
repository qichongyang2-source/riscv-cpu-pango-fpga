`timescale 1ns/1ps
//=============================================================================
//  imem.v : 指令存储器（64 KB = 4096 x 128 位）
//  宽度等于一个 Cache 行（16 B），一次读回整行 → 单读端口，可推断 BRAM
//=============================================================================
module imem #(
    parameter LINES     = 4096,
    parameter INIT_FILE = "imem.hex",
    parameter INIT_EN   = 1
)(
    input  wire         clk,

    input  wire [31:0]  addr,          // 行基地址（低 4 位忽略）
    input  wire         re,
    output reg  [127:0] rdata,         // 整行：{[3],[2],[1],[0]}
    output reg          rvalid
);

    reg [127:0] mem [0:LINES-1];
    integer i;

`ifdef SIM_INIT
    initial begin
        for (i = 0; i < LINES; i = i + 1)
            mem[i] = 128'd0;
        if (INIT_EN)
            $readmemh(INIT_FILE, mem);
    end
`else
    initial begin
        for (i = 0; i < LINES; i = i + 1)
            mem[i] = 128'd0;
    end
`endif

    always @(posedge clk) begin
        if (re)
            rdata <= mem[addr[15:4]];
        rvalid <= re;
    end

endmodule
