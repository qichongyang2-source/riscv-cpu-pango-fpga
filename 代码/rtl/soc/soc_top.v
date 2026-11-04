`timescale 1ns/1ps
//=============================================================================
//  soc_top.v : 片上系统顶层
//  地址空间:
//    0x0000_0000 - 0x0000_FFFF : IMEM  (64 KB, 经 I-Cache 访问)
//    0x1000_0000 - 0x1000_FFFF : DMEM  (64 KB, 经 D-Cache 访问)
//    0x2000_0000 - 0x2000_000F : UART  (0x00 数据, 0x04 状态)
//    0x2000_1000 - 0x2000_100F : GPIO  (0x00 out, 0x04 in, 0x08 oe)
//    0x2000_2000 - 0x2000_200F : TIMER (mtime lo/hi, mtimecmp lo/hi)
//    0x3000_0000              : 仿真测试退出寄存器
//
//  I-Cache / D-Cache 均为 2 KB 直接映射；外设访问不经过 D-Cache
//=============================================================================
`include "riscv_defs.vh"

module soc_top #(
    parameter [31:0] RESET_VEC  = 32'h0000_0000,
    parameter [31:0] MTVEC_INIT = 32'h0000_0040,
    parameter        IMEM_FILE  = "imem.hex",
    parameter        DMEM_FILE  = "dmem.hex",
    parameter        MEM_INIT_EN = 1,
    parameter        CLKS_PER_BIT = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    // UART
    output wire        uart_tx,
    input  wire        uart_rx,

    // 外部中断输入（板级）
    input  wire        irq_ext_i,

    // GPIO
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_oe,
    input  wire [31:0] gpio_in,

    // 测试控制
    output wire        test_done,
    output wire        test_pass,
    output wire [31:0] test_code,

    // 调试
    output wire [31:0] dbg_pc
);

    //------------------------- 内核 <-> Cache ---------------------------------
    wire [31:0] imem_addr, imem_rdata;
    wire        imem_req;
    wire        ic_stall;

    wire [31:0] d_addr, d_wdata, d_rdata;
    wire [3:0]  d_be;
    wire        d_we, d_re;
    wire        dc_stall;

    wire [31:0] dc_rdata;

    wire        timer_irq;
    wire        irq_ext;

    // 软件中断寄存器：写 0x2000_3000 bit0 = 1 拉起 MEIP（用于自测）
    reg         irq_sw;
    wire        sel_irq = (d_addr[31:12] == 20'h20003);
    wire        irq_we  = d_we && sel_irq;

    always @(posedge clk) begin
        if (!rst_n)      irq_sw <= 1'b0;
        else if (irq_we) irq_sw <= d_wdata[0];
    end

    assign irq_ext = irq_sw | irq_ext_i;

    //------------------------- I-Cache <-> IMEM ------------------------------
    wire [31:0]  ic_mem_addr;
    wire [127:0] ic_mem_rdata;
    wire        ic_mem_re;

    //------------------------- D-Cache <-> DMEM ------------------------------
    wire [31:0]  dc_mem_addr, dc_mem_wdata;
    wire [127:0] dc_mem_rdata;
    wire [3:0]  dc_mem_be;
    wire        dc_mem_re, dc_mem_we;

    //------------------------- 地址译码 --------------------------------------
    wire sel_dmem  = (d_addr[31:16] == 16'h1000);
    wire sel_uart  = (d_addr[31:12] == 20'h20000);
    wire sel_gpio  = (d_addr[31:12] == 20'h20001);
    wire sel_timer = (d_addr[31:12] == 20'h20002);
    wire sel_test  = (d_addr[31:12] == 20'h30000);
    wire sel_ai    = (d_addr[31:12] == 20'h20004);   // AI 寄存器
    wire sel_aibuf = (d_addr[31:13] == 19'h10004);   // AI 本地缓冲 8 KB（0x2000_8000-9FFF）

    // Cache 只处理 DMEM 段；外设访问绕行
    wire dc_re = d_re && sel_dmem;
    wire dc_we = d_we && sel_dmem;

    //------------------------- 内核 ------------------------------------------
    riscv_core #(
        .RESET_VEC (RESET_VEC),
        .MTVEC_INIT(MTVEC_INIT)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_req   (imem_req),
        .imem_rdata (imem_rdata),
        .dmem_addr  (d_addr),
        .dmem_wdata (d_wdata),
        .dmem_be    (d_be),
        .dmem_we    (d_we),
        .dmem_re    (d_re),
        .dmem_rdata (d_rdata),
        .irq_timer  (timer_irq),
        .irq_ext    (irq_ext),
        .if_stall   (ic_stall),
        .mem_stall  (dc_stall),
        .commit_valid(),
        .commit_pc  (),
        .commit_instr()
    );

    assign dbg_pc = imem_addr;

    //------------------------- I-Cache ---------------------------------------
    icache #(.SETS(64)) u_icache (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (imem_addr),
        .rdata    (imem_rdata),
        .hit      (),
        .stall    (ic_stall),
        .mem_addr (ic_mem_addr),
        .mem_re   (ic_mem_re),
        .mem_rdata(ic_mem_rdata),
        .hit_cnt  (),
        .miss_cnt ()
    );

    //------------------------- D-Cache ---------------------------------------
    dcache #(.SETS(64)) u_dcache (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (d_addr),
        .wdata    (d_wdata),
        .be       (d_be),
        .we       (dc_we),
        .re       (dc_re),
        .rdata    (dc_rdata),
        .hit      (),
        .stall    (dc_stall),
        .mem_addr (dc_mem_addr),
        .mem_re   (dc_mem_re),
        .mem_we   (dc_mem_we),
        .mem_wdata(dc_mem_wdata),
        .mem_be   (dc_mem_be),
        .mem_rdata(dc_mem_rdata),
        .hit_cnt  (),
        .miss_cnt ()
    );

    wire uart_we  = d_we && sel_uart;
    wire gpio_we  = d_we && sel_gpio;
    wire timer_we = d_we && sel_timer;
    wire test_we  = d_we && sel_test;

    //------------------------- 指令存储器 ------------------------------------
    imem #(
        .LINES    (4096),
        .INIT_FILE(IMEM_FILE),
        .INIT_EN  (MEM_INIT_EN)
    ) u_imem (
        .clk   (clk),
        .addr  (ic_mem_addr),
        .re    (ic_mem_re),
        .rdata (ic_mem_rdata),
        .rvalid()
    );

    //------------------------- 数据存储器 ------------------------------------
    dmem #(
        .LINES    (4096),
        .INIT_FILE(DMEM_FILE),
        .INIT_EN  (MEM_INIT_EN)
    ) u_dmem (
        .clk   (clk),
        .addr  (dc_mem_addr),
        .wdata (dc_mem_wdata),
        .be    (dc_mem_be),
        .we    (dc_mem_we),
        .re    (dc_mem_re),
        .rdata (dc_mem_rdata),
        .rvalid()
    );

    //------------------------- UART ------------------------------------------
    wire [31:0] uart_rdata;
    wire        uart_tx_busy;
    wire [7:0]  uart_rx_data;
    wire        uart_rx_valid;
    wire        uart_start = uart_we && (d_addr[3:2] == 2'd0);

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk  (clk),
        .rst_n(rst_n),
        .data (d_wdata[7:0]),
        .start(uart_start),
        .tx   (uart_tx),
        .busy (uart_tx_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk  (clk),
        .rst_n(rst_n),
        .rx   (uart_rx),
        .data (uart_rx_data),
        .valid(uart_rx_valid)
    );

    assign uart_rdata = (d_addr[3:2] == 2'd0) ?
                        {24'd0, uart_rx_data} :
                        {30'd0, uart_rx_valid, uart_tx_busy};

    //------------------------- GPIO ------------------------------------------
    wire [31:0] gpio_rdata;

    gpio u_gpio (
        .clk     (clk),
        .rst_n   (rst_n),
        .we      (gpio_we),
        .addr    (d_addr[3:2]),
        .wdata   (d_wdata),
        .rdata   (gpio_rdata),
        .gpio_in (gpio_in),
        .gpio_out(gpio_out),
        .gpio_oe (gpio_oe)
    );

    //------------------------- TIMER -----------------------------------------
    wire [31:0] timer_rdata;

    timer u_timer (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (timer_we),
        .addr (d_addr[3:2]),
        .wdata(d_wdata),
        .rdata(timer_rdata),
        .irq  (timer_irq)
    );

    //------------------------- AI 加速器 -------------------------------------
    wire [31:0] ai_rdata;
    wire        ai_busy, ai_done;

    ai_accel #(.LANES(4)) u_ai (
        .clk     (clk),
        .rst_n   (rst_n),
        .cs_reg  (sel_ai),
        .cs_buf  (sel_aibuf),
        .reg_idx (d_addr[7:2]),
        .buf_idx (d_addr[12:2]),
        .we      (d_we),
        .be      (d_be),
        .wdata   (d_wdata),
        .rdata   (ai_rdata),
        .busy    (ai_busy),
        .done    (ai_done)
    );

    //------------------------- 读数据回选 ------------------------------------
    // DMEM 数据由 D-Cache 提供；外设走独立通路
    reg [31:0] d_rdata_mux;

    always @(*) begin
        if (sel_dmem)       d_rdata_mux = dc_rdata;
        else if (sel_uart)  d_rdata_mux = uart_rdata;
        else if (sel_gpio)  d_rdata_mux = gpio_rdata;
        else if (sel_timer) d_rdata_mux = timer_rdata;
        else if (sel_irq)   d_rdata_mux = {31'd0, irq_ext};
        else if (sel_ai || sel_aibuf) d_rdata_mux = ai_rdata;
        else                d_rdata_mux = 32'd0;
    end

    assign d_rdata = d_rdata_mux;

    //------------------------- 测试退出 --------------------------------------
    reg        test_done_r;
    reg        test_pass_r;
    reg [31:0] test_code_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            test_done_r <= 1'b0;
            test_pass_r <= 1'b0;
            test_code_r <= 32'd0;
        end else if (test_we) begin
            test_done_r <= 1'b1;
            test_pass_r <= d_wdata[0];
            test_code_r <= d_wdata[31:1];
        end
    end

    assign test_done = test_done_r;
    assign test_pass = test_pass_r;
    assign test_code = test_code_r;

endmodule
