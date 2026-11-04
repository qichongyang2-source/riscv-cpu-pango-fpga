`timescale 1ns/1ps
//=============================================================================
//  imem.v : 指令存储器（64 KB = 4096 x 128 位）
//  宽度等于一个 Cache 行（16 B），一次读回整行 → 单读端口，可推断 BRAM
//
//  初始化约定：
//   - 仿真（SIM_INIT）：整行清零后 $readmemh，避免未初始化 X
//   - 综合：默认不清零、不初值（BRAM 上电内容不定）；
//     需要预置程序时由 flatten.py 在 __MEM_INIT_HOOK__ 处插入 initial 赋值，
//     或由 PDS 的存储器初始化文件提供
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

    always @(posedge clk) begin
        if (re)
            rdata <= mem[addr[15:4]];
        rvalid <= re;
    end

endmodule
