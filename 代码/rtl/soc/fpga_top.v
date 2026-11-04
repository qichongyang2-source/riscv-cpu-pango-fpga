`timescale 1ns/1ps
//=============================================================================
//  fpga_top.v : 板级顶层（紫光同创 PGL22G 等）
//  - 复位同步
//  - SoC + UART + LED + 按键
//  - 上板时建议用 PLL 输出 100 MHz 替换直连时钟
//=============================================================================
module fpga_top #(
    // 综合时置 0：程序由 PDS 的 BRAM 初始化文件加载
    parameter MEM_INIT_EN = 0
)(
    input  wire        clk,          // 板载 50 MHz
    input  wire        rst_n,        // 低有效复位（按键）

    input  wire        uart_rx,
    output wire        uart_tx,

    input  wire [3:0]  key,
    output wire [3:0]  led
);

    //------------------------- 复位同步 --------------------------------------
    reg [2:0] rst_sync;
    always @(posedge clk) begin
        if (!rst_n) rst_sync <= 3'b000;
        else        rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire sys_rst_n = rst_sync[2];

    //------------------------- SoC -------------------------------------------
    wire [31:0] gpio_out, gpio_oe;
    wire        test_done, test_pass;
    wire [31:0] test_code;
    wire [31:0] dbg_pc;

    soc_top #(
        .MEM_INIT_EN(MEM_INIT_EN)
    ) u_soc (
        .clk      (clk),
        .rst_n    (sys_rst_n),
        .uart_tx  (uart_tx),
        .uart_rx  (uart_rx),
        .irq_ext_i(1'b0),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe),
        .gpio_in  ({28'd0, key}),
        .test_done(test_done),
        .test_pass(test_pass),
        .test_code(test_code),
        .dbg_pc   (dbg_pc)
    );

    //------------------------- 状态指示 --------------------------------------
    // 运行中：LED 显示 PC 高位；测试通过：全亮；失败：显示错误码低 4 位
    assign led = test_done ? (test_pass ? 4'hF : ~test_code[3:0]) : dbg_pc[5:2];

endmodule
