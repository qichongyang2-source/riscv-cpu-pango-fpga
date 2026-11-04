`timescale 1ns/1ps
//=============================================================================
//  riscv_csr.v : 机器模式 CSR 寄存器组 + 异常/中断入口
//  - 读端口工作在 EX 级（组合读）
//  - 写端口工作在 MEM 级（随指令提交，遇到 trap 时由上层屏蔽）
//  - 支持: mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip、
//          mcycle/minstret、cycle/instret、只读 ID 寄存器
//=============================================================================
`include "riscv_defs.vh"

module riscv_csr #(
    parameter [31:0] MTVEC_INIT = 32'h0000_0040
)(
    input  wire        clk,
    input  wire        rst_n,

    //------------------- 读端口 (EX) ----------------------------------------
    input  wire [11:0] raddr,
    output reg  [31:0] rdata,

    //------------------- 写端口 (MEM, 已提交) --------------------------------
    input  wire        we,
    input  wire [11:0] waddr,
    input  wire [1:0]  wop,
    input  wire [31:0] wdata,

    //------------------- 异常 / 返回 -----------------------------------------
    input  wire        trap,          // 进入 trap（异常或中断）
    input  wire        trap_is_irq,
    input  wire [3:0]  trap_cause,
    input  wire [31:0] trap_tval,
    input  wire [31:0] trap_epc,
    input  wire        mret,

    //------------------- 中断 -----------------------------------------------
    input  wire        irq_timer,     // MTIP (电平)
    input  wire        irq_ext,       // MEIP (电平)
    output wire        irq_pending,   // mstatus.MIE & mie & mip
    output wire [3:0]  irq_cause,     // 优先级编码后的中断原因

    //------------------- 输出给 PC 逻辑 -------------------------------------
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,

    //------------------- 退休计数 -------------------------------------------
    input  wire        retire
);

    //------------------------ CSR 寄存器 -------------------------------------
    reg [31:0] mstatus_r;
    reg [31:0] mie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;

    reg [63:0] mcycle_r;
    reg [63:0] minstret_r;

    // mstatus 可写位: MIE[3], MPIE[7], MPP[12:11]
    wire [31:0] MSTATUS_MASK = 32'h0000_1888;
    wire [31:0] MIE_MASK     = 32'h0000_0888;   // MEIE/MTIE/MSIE

    wire [31:0] mip_r = {20'd0, irq_ext, 3'd0, irq_timer, 7'd0}; // MEIP=11, MTIP=7

    wire ext_irq = mstatus_r[3] && mie_r[11] && irq_ext;
    wire tmr_irq = mstatus_r[3] && mie_r[7]  && irq_timer;

    assign irq_pending = ext_irq | tmr_irq;
    assign irq_cause   = ext_irq ? `CAUSE_M_EXT_IRQ : `CAUSE_M_TIMER_IRQ;

    // mtvec[1:0] != 0 时为向量模式：中断入口 = base + 4*cause
    wire [31:0] mtvec_base = {mtvec_r[31:2], 2'b00};
    assign mtvec_o = ((mtvec_r[1:0] == 2'b01) && trap_is_irq)
                     ? (mtvec_base + {26'd0, trap_cause, 2'b00})
                     : mtvec_base;
    assign mepc_o  = mepc_r;

    //------------------------ 读多路选择 -------------------------------------
    always @(*) begin
        case (raddr)
            `CSR_MSTATUS  : rdata = mstatus_r;
            `CSR_MIE      : rdata = mie_r;
            `CSR_MTVEC    : rdata = mtvec_r;
            `CSR_MSCRATCH : rdata = mscratch_r;
            `CSR_MEPC     : rdata = mepc_r;
            `CSR_MCAUSE   : rdata = mcause_r;
            `CSR_MTVAL    : rdata = mtval_r;
            `CSR_MIP      : rdata = mip_r;
            `CSR_MCYCLE   : rdata = mcycle_r[31:0];
            `CSR_MINSTRET : rdata = minstret_r[31:0];
            `CSR_MCYCLEH  : rdata = mcycle_r[63:32];
            `CSR_MINSTRETH: rdata = minstret_r[63:32];
            `CSR_CYCLE    : rdata = mcycle_r[31:0];
            `CSR_INSTRET  : rdata = minstret_r[31:0];
            `CSR_CYCLEH   : rdata = mcycle_r[63:32];
            `CSR_INSTRETH : rdata = minstret_r[63:32];
            `CSR_MVENDORID: rdata = 32'h0000_0000;
            `CSR_MARCHID  : rdata = 32'h0000_0001;
            `CSR_MIMPID   : rdata = 32'h0000_0001;
            `CSR_MHARTID  : rdata = 32'h0000_0000;
            default       : rdata = 32'd0;
        endcase
    end

    //------------------------ 写数据计算 -------------------------------------
    reg  [31:0] w_old;
    always @(*) begin
        case (waddr)
            `CSR_MSTATUS  : w_old = mstatus_r;
            `CSR_MIE      : w_old = mie_r;
            `CSR_MTVEC    : w_old = mtvec_r;
            `CSR_MSCRATCH : w_old = mscratch_r;
            `CSR_MEPC     : w_old = mepc_r;
            `CSR_MCAUSE   : w_old = mcause_r;
            `CSR_MTVAL    : w_old = mtval_r;
            `CSR_MCYCLE   : w_old = mcycle_r[31:0];
            `CSR_MINSTRET : w_old = minstret_r[31:0];
            `CSR_MCYCLEH  : w_old = mcycle_r[63:32];
            `CSR_MINSTRETH: w_old = minstret_r[63:32];
            default       : w_old = 32'd0;
        endcase
    end

    wire [31:0] w_new = (wop == `CSR_RW) ? wdata :
                        (wop == `CSR_RS) ? (w_old | wdata) :
                                           (w_old & ~wdata);

    wire w_en = we && ((wop == `CSR_RW) || (wdata != 32'd0));

    //------------------------ 时序更新 ---------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mstatus_r  <= 32'd0;
            mie_r      <= 32'd0;
            mtvec_r    <= MTVEC_INIT;
            mscratch_r <= 32'd0;
            mepc_r     <= 32'd0;
            mcause_r   <= 32'd0;
            mtval_r    <= 32'd0;
            mcycle_r   <= 64'd0;
            minstret_r <= 64'd0;
        end else begin
            // 周期计数
            mcycle_r <= mcycle_r + 64'd1;
            if (retire)
                minstret_r <= minstret_r + 64'd1;

            if (trap) begin
                mepc_r          <= {trap_epc[31:2], 2'b00};
                mcause_r        <= {trap_is_irq, 27'd0, trap_cause};
                mtval_r         <= trap_tval;
                mstatus_r[7]    <= mstatus_r[3];        // MPIE <- MIE
                mstatus_r[3]    <= 1'b0;                // MIE  <- 0
                mstatus_r[12:11]<= 2'b11;               // MPP  <- M
            end else if (mret) begin
                mstatus_r[3]    <= mstatus_r[7];        // MIE  <- MPIE
                mstatus_r[7]    <= 1'b1;                // MPIE <- 1
                mstatus_r[12:11]<= 2'b00;               // MPP  <- U
            end else if (w_en) begin
                case (waddr)
                    `CSR_MSTATUS : mstatus_r <= (w_old & ~MSTATUS_MASK) | (w_new & MSTATUS_MASK);
                    `CSR_MIE     : mie_r     <= w_new & MIE_MASK;
                    `CSR_MTVEC   : mtvec_r   <= w_new;
                    `CSR_MSCRATCH: mscratch_r<= w_new;
                    `CSR_MEPC    : mepc_r    <= {w_new[31:2], 2'b00};
                    `CSR_MCAUSE  : mcause_r  <= w_new;
                    `CSR_MTVAL   : mtval_r   <= w_new;
                    `CSR_MCYCLE  : mcycle_r[31:0]    <= w_new;
                    `CSR_MINSTRET: minstret_r[31:0]  <= w_new;
                    `CSR_MCYCLEH : mcycle_r[63:32]   <= w_new;
                    `CSR_MINSTRETH: minstret_r[63:32]<= w_new;
                    default      : ; // 只读或未实现，写忽略
                endcase
            end
        end
    end

endmodule
