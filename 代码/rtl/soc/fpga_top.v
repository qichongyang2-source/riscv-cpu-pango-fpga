`timescale 1ns/1ps
//=============================================================================
//  fpga_top.v : 板级顶层（紫光同创 PG2L200H / Logos2，实验箱 DUT）
//
//  板卡档案（平台内置）：
//    clk      D18   27 MHz（37.037 ns）
//    rst_n    C22   低有效（远程平台可能长期为低，默认不参与复位）
//    LED[3:0] U16/U15/V17/V16  低电平点亮
//    uart_tx  AB26  / uart_rx AC26
//    KEY[3:0] U21/W24/V24/AA23 低电平按下
//
//  说明：
//   - 默认使用内部上电复位；需要实体复位键时把 USE_EXTERNAL_RESET 置 1。
//   - 按键做 5 ms 消抖后取下降沿翻转（孪生端虚拟按键为边界扫描驱动，
//     不能用电平直通）。
//   - UART 分频按 27 MHz / 115200 计算为 234。
//=============================================================================
module fpga_top #(
    parameter CLK_HZ             = 27000000,
    parameter BAUD               = 115200,
    parameter USE_EXTERNAL_RESET = 0,
    parameter KEY_DEBOUNCE_MS    = 5,
    parameter MEM_INIT_EN        = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        uart_rx,
    output wire        uart_tx,

    input  wire [3:0]  key,
    output wire [3:0]  led
);

    localparam CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;   // 234 @ 27 MHz / 115200
    localparam POR_CYCLES   = 1024;
    localparam DEB_CYCLES   = (CLK_HZ / 1000) * KEY_DEBOUNCE_MS;  // 135000 @ 27 MHz

    //------------------------- 内部上电复位 --------------------------------
    reg [15:0] por_cnt = 16'd0;   // 上电初值（FPGA 触发器上电为 0，仿真也需显式给出）
    reg        por_n   = 1'b0;

    always @(posedge clk) begin
        if (por_cnt >= POR_CYCLES[15:0]) begin
            por_n <= 1'b1;
        end else begin
            por_cnt <= por_cnt + 16'd1;
            por_n   <= 1'b0;
        end
    end

    wire sys_rst_n = (USE_EXTERNAL_RESET != 0) ? (por_n & rst_n) : por_n;

    //------------------------- 按键同步与消抖 -------------------------------
    reg [3:0] key_sync0, key_sync1;

    always @(posedge clk) begin
        key_sync0 <= ~key;          // 低有效 -> 高有效
        key_sync1 <= key_sync0;
    end

    reg [3:0] key_toggle;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_key
            reg [31:0] cnt;
            reg        stable;

            always @(posedge clk) begin
                if (!sys_rst_n) begin
                    cnt    <= 32'd0;
                    stable <= 1'b0;
                end else if (key_sync1[gi] == stable) begin
                    cnt <= 32'd0;
                end else if (cnt >= DEB_CYCLES - 1) begin
                    stable <= key_sync1[gi];
                    cnt    <= 32'd0;
                end else begin
                    cnt <= cnt + 32'd1;
                end
            end

            always @(posedge clk) begin
                if (!sys_rst_n)
                    key_toggle[gi] <= 1'b0;
                else if ((cnt >= DEB_CYCLES - 1) && (key_sync1[gi] != stable) && key_sync1[gi])
                    key_toggle[gi] <= ~key_toggle[gi];
            end
        end
    endgenerate

    //------------------------- 心跳 -----------------------------------------
    reg [25:0] heartbeat = 26'd0;
    always @(posedge clk) begin
        if (!sys_rst_n) heartbeat <= 26'd0;
        else            heartbeat <= heartbeat + 26'd1;
    end

    //------------------------- SoC ------------------------------------------
    wire [31:0] gpio_out, gpio_oe;
    wire        test_done, test_pass;
    wire [31:0] test_code;
    wire [31:0] dbg_pc;

    soc_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .MEM_INIT_EN (MEM_INIT_EN)
    ) u_soc (
        .clk       (clk),
        .rst_n     (sys_rst_n),
        .irq_ext_i (1'b0),
        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),
        .gpio_in   ({28'd0, key}),
        .test_done (test_done),
        .test_pass (test_pass),
        .test_code (test_code),
        .dbg_pc    (dbg_pc)
    );

    //------------------------- 状态指示（低电平点亮） -----------------------
    // LED[3] 测试完成  LED[2] 测试通过  LED[1] 按键翻转  LED[0] 心跳
    assign led = ~{test_done, test_pass, key_toggle[0], heartbeat[24]};

endmodule
