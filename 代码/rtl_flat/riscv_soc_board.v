`timescale 1ns/1ps
// ==========================================================================
//  riscv_soc_flat.v : 由 sw/tools/flatten.py 自动生成，请勿手工编辑
//  包含：RV32I 五级流水 CPU + Cache/主存 + 外设 + AI 加速器 + 板级顶层
//  顶层模块：fpga_top
// ==========================================================================

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_defs.vh
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_defs.vh : 全局常量定义 (RV32I 基础整数指令集 + Zicsr)
//  赛题1 : 基于紫光同创 RISC-V 指令集 CPU 设计
//=============================================================================

//------------------------- 指令 opcode ---------------------------------------
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_IMM      7'b0010011
`define OP_REG      7'b0110011
`define OP_FENCE    7'b0001111
`define OP_SYSTEM   7'b1110011

//------------------------- ALU 操作码 ----------------------------------------
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_SLL     4'd2
`define ALU_SLT     4'd3
`define ALU_SLTU    4'd4
`define ALU_XOR     4'd5
`define ALU_SRL     4'd6
`define ALU_SRA     4'd7
`define ALU_OR      4'd8
`define ALU_AND     4'd9
`define ALU_PASS_B  4'd10
`define ALU_PASS_A  4'd11

//------------------------- 写回源选择 ----------------------------------------
`define WB_ALU      2'd0
`define WB_MEM      2'd1
`define WB_PC4      2'd2
`define WB_CSR      2'd3

//------------------------- 分支类型 ------------------------------------------
`define BR_NONE     3'd0
`define BR_EQ       3'd1
`define BR_NE       3'd2
`define BR_LT       3'd3
`define BR_GE       3'd4
`define BR_LTU      3'd5
`define BR_GEU      3'd6

//------------------------- 跳转类型 ------------------------------------------
`define JUMP_NONE   2'd0
`define JUMP_JAL    2'd1
`define JUMP_JALR   2'd2

//------------------------- CSR 操作 ------------------------------------------
`define CSR_NONE    2'd0
`define CSR_RW      2'd1
`define CSR_RS      2'd2
`define CSR_RC      2'd3

//------------------------- 异常/中断原因码 (mcause) --------------------------
`define CAUSE_INSTR_MISALIGN   4'd0
`define CAUSE_ILLEGAL_INSTR    4'd2
`define CAUSE_BREAKPOINT       4'd3
`define CAUSE_LOAD_MISALIGN    4'd4
`define CAUSE_STORE_MISALIGN   4'd6
`define CAUSE_ECALL_M          4'd11
`define CAUSE_M_TIMER_IRQ      4'd7
`define CAUSE_M_EXT_IRQ        4'd11

//------------------------- CSR 地址 ------------------------------------------
`define CSR_MSTATUS   12'h300
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_CYCLE     12'hC00
`define CSR_INSTRET   12'hC02
`define CSR_CYCLEH    12'hC80
`define CSR_INSTRETH  12'hC82
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_alu.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_alu.v : 32 位算术逻辑单元
//=============================================================================

module riscv_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y
);

    always @(*) begin
        case (op)
            `ALU_ADD   : y = a + b;
            `ALU_SUB   : y = a - b;
            `ALU_SLL   : y = a << b[4:0];
            `ALU_SLT   : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            `ALU_SLTU  : y = (a < b) ? 32'd1 : 32'd0;
            `ALU_XOR   : y = a ^ b;
            `ALU_SRL   : y = a >> b[4:0];
            `ALU_SRA   : y = $signed(a) >>> b[4:0];
            `ALU_OR    : y = a | b;
            `ALU_AND   : y = a & b;
            `ALU_PASS_B: y = b;
            `ALU_PASS_A: y = a;
            default    : y = 32'd0;
        endcase
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_regfile.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_regfile.v : 32 x 32 位通用寄存器堆
//  - 两个组合读端口，一个同步写端口（写优先，x0 恒为 0）
//=============================================================================
module riscv_regfile (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_lsu.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_lsu.v : 访存单元
//  - 把字地址 + funct3 转换成字节使能 / 写数据
//  - 把读回的字数据按 funct3 做字节/半字提取与符号扩展
//  说明: 本设计在硬件上支持非对齐访问（由字节通路完成），不产生
//        load/store misaligned 异常。
//=============================================================================
module riscv_lsu (
    input  wire [1:0]  addr_lo,      // 字节地址低 2 位
    input  wire [2:0]  funct3,
    input  wire [31:0] store_data,   // 已转发后的 rs2
    input  wire [31:0] rdata,        // 存储器读回字

    output reg  [3:0]  be,           // 字节写使能
    output reg  [31:0] wdata,        // 写数据（重复铺满各字节通道）
    output reg  [31:0] load_data     // 扩展后的读数据
);

    //--------------------------- 写通路 --------------------------------------
    always @(*) begin
        be    = 4'b0000;
        wdata = store_data;
        case (funct3)
            3'b000: begin // SB
                be    = 4'b0001 << addr_lo;
                wdata = {4{store_data[7:0]}};
            end
            3'b001: begin // SH
                be    = addr_lo[1] ? 4'b1100 : 4'b0011;
                wdata = {2{store_data[15:0]}};
            end
            3'b010: begin // SW
                be    = 4'b1111;
                wdata = store_data;
            end
            default: begin
                be    = 4'b0000;
                wdata = store_data;
            end
        endcase
    end

    //--------------------------- 读通路 --------------------------------------
    wire [7:0]  byte_sel  = rdata[{addr_lo, 3'b000} +: 8];
    wire [15:0] half_sel  = addr_lo[1] ? rdata[31:16] : rdata[15:0];

    always @(*) begin
        case (funct3)
            3'b000: load_data = {{24{byte_sel[7]}}, byte_sel};   // LB
            3'b001: load_data = {{16{half_sel[15]}}, half_sel};  // LH
            3'b010: load_data = rdata;                           // LW
            3'b100: load_data = {24'd0, byte_sel};               // LBU
            3'b101: load_data = {16'd0, half_sel};               // LHU
            default: load_data = rdata;
        endcase
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_decoder.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_decoder.v : RV32I 指令译码 / 控制单元
//  输出控制信号 + 立即数；同时给出非法指令标志与系统指令标志
//=============================================================================

module riscv_decoder (
    input  wire [31:0] instr,

    output reg         illegal,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output reg         use_rs1,
    output reg         use_rs2,
    output reg  [31:0] imm,

    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         alu_src_a_pc,
    output reg         alu_src_b_imm,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  wb_sel,

    output reg  [2:0]  branch_type,
    output reg  [1:0]  jump_type,

    output reg         is_muldiv,
    output reg  [2:0]  muldiv_op,

    output reg  [1:0]  csr_op,
    output reg         csr_imm,
    output reg  [11:0] csr_addr,

    output reg         is_ecall,
    output reg         is_ebreak,
    output reg         is_mret
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd  = instr[11:7];

    //--------------------------- 立即数生成 ----------------------------------
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    //--------------------------- 译码主逻辑 ----------------------------------
    always @(*) begin
        illegal        = 1'b0;
        use_rs1        = 1'b0;
        use_rs2        = 1'b0;
        imm            = 32'd0;
        reg_write      = 1'b0;
        mem_read       = 1'b0;
        mem_write      = 1'b0;
        alu_src_a_pc   = 1'b0;
        alu_src_b_imm  = 1'b0;
        alu_op         = `ALU_ADD;
        wb_sel         = `WB_ALU;
        branch_type    = `BR_NONE;
        jump_type      = `JUMP_NONE;
        is_muldiv     = 1'b0;
        muldiv_op     = 3'd0;
        csr_op         = `CSR_NONE;
        csr_imm        = 1'b0;
        csr_addr       = 12'd0;
        is_ecall       = 1'b0;
        is_ebreak      = 1'b0;
        is_mret        = 1'b0;

        case (opcode)
            //-----------------------------------------------------------------
            `OP_LUI: begin
                imm           = imm_u;
                reg_write     = 1'b1;
                alu_src_b_imm = 1'b1;
                alu_op        = `ALU_PASS_B;
                wb_sel        = `WB_ALU;
            end
            //-----------------------------------------------------------------
            `OP_AUIPC: begin
                imm           = imm_u;
                reg_write     = 1'b1;
                alu_src_a_pc  = 1'b1;
                alu_src_b_imm = 1'b1;
                alu_op        = `ALU_ADD;
                wb_sel        = `WB_ALU;
            end
            //-----------------------------------------------------------------
            `OP_JAL: begin
                imm        = imm_j;
                reg_write  = 1'b1;
                jump_type  = `JUMP_JAL;
                wb_sel     = `WB_PC4;
            end
            //-----------------------------------------------------------------
            `OP_JALR: begin
                if (funct3 == 3'b000) begin
                    imm       = imm_i;
                    reg_write = 1'b1;
                    use_rs1   = 1'b1;
                    jump_type = `JUMP_JALR;
                    wb_sel    = `WB_PC4;
                end else begin
                    illegal = 1'b1;
                end
            end
            //-----------------------------------------------------------------
            `OP_BRANCH: begin
                imm     = imm_b;
                use_rs1 = 1'b1;
                use_rs2 = 1'b1;
                case (funct3)
                    3'b000: branch_type = `BR_EQ;
                    3'b001: branch_type = `BR_NE;
                    3'b100: branch_type = `BR_LT;
                    3'b101: branch_type = `BR_GE;
                    3'b110: branch_type = `BR_LTU;
                    3'b111: branch_type = `BR_GEU;
                    default: illegal = 1'b1;
                endcase
            end
            //-----------------------------------------------------------------
            `OP_LOAD: begin
                imm       = imm_i;
                reg_write = 1'b1;
                mem_read  = 1'b1;
                use_rs1   = 1'b1;
                alu_src_b_imm = 1'b1;
                alu_op    = `ALU_ADD;
                wb_sel    = `WB_MEM;
                if ((funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111))
                    illegal = 1'b1;
            end
            //-----------------------------------------------------------------
            `OP_STORE: begin
                imm           = imm_s;
                mem_write     = 1'b1;
                use_rs1       = 1'b1;
                use_rs2       = 1'b1;
                alu_src_b_imm = 1'b1;
                alu_op        = `ALU_ADD;
                if ((funct3 == 3'b011) || (funct3 > 3'b010))
                    illegal = 1'b1;
            end
            //-----------------------------------------------------------------
            `OP_IMM: begin
                imm           = imm_i;
                reg_write     = 1'b1;
                use_rs1       = 1'b1;
                alu_src_b_imm = 1'b1;
                wb_sel        = `WB_ALU;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: begin
                        alu_op = `ALU_SLL;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000)      alu_op = `ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = `ALU_SRA;
                        else                           illegal = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            //-----------------------------------------------------------------
            `OP_REG: begin
                reg_write     = 1'b1;
                use_rs1       = 1'b1;
                use_rs2       = 1'b1;
                alu_src_b_imm = 1'b0;
                wb_sel        = `WB_ALU;
                case (funct3)
                    3'b000: alu_op = (funct7 == 7'b0100000) ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = (funct7 == 7'b0100000) ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    default: illegal = 1'b1;
                endcase
                if (funct7 == 7'b0000001) begin
                    // M 扩展：MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
                    is_muldiv = 1'b1;
                    muldiv_op = funct3;
                    wb_sel    = `WB_ALU;
                end else if (funct7 == 7'b0100000) begin
                    // funct7 = 0100000 仅对 SUB(f3=000) / SRA(f3=101) 合法
                    if ((funct3 != 3'b000) && (funct3 != 3'b101))
                        illegal = 1'b1;
                end else if (funct7 != 7'b0000000) begin
                    illegal = 1'b1;
                end
            end
            //-----------------------------------------------------------------
            `OP_FENCE: begin
                // FENCE / FENCE.I : 本设计为顺序单发射，直接当 NOP 处理
                if (funct3 > 3'b001) illegal = 1'b1;
            end
            //-----------------------------------------------------------------
            `OP_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        if (instr == 32'h0000_0073) begin
                            is_ecall = 1'b1;
                        end else if (instr == 32'h0010_0073) begin
                            is_ebreak = 1'b1;
                        end else if (instr == 32'h3020_0073) begin
                            is_mret = 1'b1;
                        end else if (instr == 32'h1050_0073) begin
                            // WFI：允许实现为 NOP（本设计取 NOP 语义）
                        end else begin
                            illegal = 1'b1;
                        end
                    end
                    3'b001, 3'b010, 3'b011: begin
                        csr_op    = funct3[1:0];
                        csr_imm   = 1'b0;
                        csr_addr  = instr[31:20];
                        reg_write = 1'b1;
                        wb_sel    = `WB_CSR;
                        use_rs1   = 1'b1;
                    end
                    3'b101, 3'b110, 3'b111: begin
                        csr_op    = funct3[1:0];
                        csr_imm   = 1'b1;
                        csr_addr  = instr[31:20];
                        reg_write = 1'b1;
                        wb_sel    = `WB_CSR;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            //-----------------------------------------------------------------
            default: illegal = 1'b1;
        endcase
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_hazard.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_hazard.v : 数据冒险检测（转发 + load-use 停顿）
//  fwd_a/fwd_b: 2'b00 = 寄存器堆, 2'b10 = EX/MEM, 2'b01 = MEM/WB
//=============================================================================
module riscv_hazard (
    // 译码级
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_use_rs1,
    input  wire       id_use_rs2,
    input  wire       id_valid,

    // 执行级 (ID/EX)
    input  wire       ex_valid,
    input  wire [4:0] ex_rd,
    input  wire       ex_reg_write,
    input  wire       ex_mem_read,
    input  wire       ex_use_rs1,
    input  wire       ex_use_rs2,
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,

    // 访存级 (EX/MEM)
    input  wire       mem_valid,
    input  wire [4:0] mem_rd,
    input  wire       mem_reg_write,
    input  wire       mem_mem_read,

    // 写回级 (MEM/WB)
    input  wire       wb_valid,
    input  wire [4:0] wb_rd,
    input  wire       wb_reg_write,

    // CSR 写后读互锁
    input  wire       id_is_csr,
    input  wire [11:0] id_csr_addr,
    input  wire       ex_csr_we,
    input  wire [11:0] ex_csr_addr,

    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b,
    output reg        load_use_stall,
    output reg        csr_stall
);

    //----------------------- 转发选择 ----------------------------------------
    always @(*) begin
        fwd_a = 2'b00;
        if (ex_use_rs1 && (ex_rs1 != 5'd0)) begin
            if (mem_valid && mem_reg_write && !mem_mem_read && (mem_rd == ex_rs1))
                fwd_a = 2'b10;                                  // EX/MEM 转发
            else if (wb_valid && wb_reg_write && (wb_rd == ex_rs1))
                fwd_a = 2'b01;                                  // MEM/WB 转发
        end
    end

    always @(*) begin
        fwd_b = 2'b00;
        if (ex_use_rs2 && (ex_rs2 != 5'd0)) begin
            if (mem_valid && mem_reg_write && !mem_mem_read && (mem_rd == ex_rs2))
                fwd_b = 2'b10;
            else if (wb_valid && wb_reg_write && (wb_rd == ex_rs2))
                fwd_b = 2'b01;
        end
    end

    //----------------------- load-use 停顿 -----------------------------------
    always @(*) begin
        load_use_stall = 1'b0;
        if (id_valid && ex_valid && ex_mem_read && (ex_rd != 5'd0)) begin
            if ((id_use_rs1 && (id_rs1 == ex_rd)) ||
                (id_use_rs2 && (id_rs2 == ex_rd)))
                load_use_stall = 1'b1;
        end
    end

    //----------------------- CSR 写后读互锁 -----------------------------------
    // csrw 在 EX 级时，紧随其后的 csrr 正处于 ID 级：多停 1 拍，
    // 让 csrr 进入 EX 时 CSR 已完成写回（写发生在 csrw 的 MEM 级末尾）。
    always @(*) begin
        csr_stall = 1'b0;
        if (id_valid && id_is_csr && ex_csr_we && (id_csr_addr == ex_csr_addr))
            csr_stall = 1'b1;
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_csr.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_csr.v : 机器模式 CSR 寄存器组 + 异常/中断入口
//  - 读端口工作在 EX 级（组合读）
//  - 写端口工作在 MEM 级（随指令提交，遇到 trap 时由上层屏蔽）
//  - 支持: mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip、
//          mcycle/minstret、cycle/instret、只读 ID 寄存器
//=============================================================================

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

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_divider.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_divider.v : 32 位恢复余数除法器（多周期，32 拍）
//    op: 3'd4 DIV, 3'd5 DIVU, 3'd6 REM, 3'd7 REMU
//    start 为单拍脉冲；busy 期间内核冻结；done 单拍有效，result 同拍有效
//    除零：商 = -1，余数 = 被除数（符合 RISC-V 规范）
//=============================================================================
module riscv_divider (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        flush,      // 指令被冲刷：放弃当前运算
    input  wire        start,
    input  wire [2:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg         busy,
    output reg         done
);

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg        state;
    reg [5:0]  cnt;
    reg [63:0] rq;          // {remainder[31:0], quotient[31:0]}
    reg [31:0] dsor;
    reg [31:0] a_q, b_q;
    reg [2:0]  op_q;
    reg        sign_q, sign_r;

    wire [31:0] a_abs = a[31] ? (~a + 32'd1) : a;
    wire [31:0] b_abs = b[31] ? (~b + 32'd1) : b;

    wire [63:0] sh     = {rq[62:0], 1'b0};
    wire [31:0] r_sh   = sh[63:32];
    wire        ge     = (r_sh >= dsor);
    wire [31:0] r_sub  = r_sh - dsor;
    wire [63:0] rq_nxt = ge ? {r_sub, sh[31:1], 1'b1} : sh;

    wire [31:0] q_raw = rq[31:0];
    wire [31:0] r_raw = rq[63:32];
    wire [31:0] q_sgn = sign_q ? (~q_raw + 32'd1) : q_raw;
    wire [31:0] r_sgn = sign_r ? (~r_raw + 32'd1) : r_raw;

    always @(*) begin
        case (op_q)
            3'd4:    result = (b_q == 32'd0) ? 32'hFFFF_FFFF : q_sgn;   // DIV
            3'd5:    result = (b_q == 32'd0) ? 32'hFFFF_FFFF : q_raw;   // DIVU
            3'd6:    result = (b_q == 32'd0) ? a_q : r_sgn;             // REM
            3'd7:    result = (b_q == 32'd0) ? a_q : r_raw;             // REMU
            default: result = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            cnt    <= 6'd0;
            rq     <= 64'd0;
            dsor   <= 32'd0;
            a_q    <= 32'd0;
            b_q    <= 32'd0;
            op_q   <= 3'd0;
            sign_q <= 1'b0;
            sign_r <= 1'b0;
            busy   <= 1'b0;
            done   <= 1'b0;
        end else if (flush) begin
            state <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        // DIVU/REMU (op[0]=1) 直接使用无符号原值
                        if (op[0]) begin
                            rq     <= {32'd0, a};
                            dsor   <= b;
                            sign_q <= 1'b0;
                            sign_r <= 1'b0;
                        end else begin
                            rq     <= {32'd0, a_abs};
                            dsor   <= b_abs;
                            sign_q <= a[31] ^ b[31];
                            sign_r <= a[31];
                        end
                        a_q    <= a;
                        b_q    <= b;
                        op_q   <= op;
                        cnt    <= 6'd32;
                        busy   <= 1'b1;
                        state  <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (cnt == 6'd0) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        rq  <= rq_nxt;
                        cnt <= cnt - 6'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_mul.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_mul.v : 32x32 乘法单元
//    输入来自 EX/MEM 流水寄存器（已转发、已寄存），输出直接进 MEM/WB
//    这样乘法器不再位于 EX 级"转发 mux -> 乘法 -> 写回 mux"的长路径上
//    op: 3'd0 MUL, 3'd1 MULH, 3'd2 MULHSU, 3'd3 MULHU
//=============================================================================
module riscv_mul (
    input  wire [2:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);

    wire signed [63:0] a_s = {{32{a[31]}}, a};
    wire signed [63:0] b_s = {{32{b[31]}}, b};
    wire        [63:0] a_u = {32'd0, a};
    wire        [63:0] b_u = {32'd0, b};

    wire [63:0] prod_ss = a_s * b_s;
    wire [63:0] prod_su = a_s * $signed(b_u);   // 有符号 x 无符号
    wire [63:0] prod_uu = a_u * b_u;

    always @(*) begin
        case (op)
            3'd0:    result = prod_ss[31:0];     // MUL
            3'd1:    result = prod_ss[63:32];    // MULH
            3'd2:    result = prod_su[63:32];    // MULHSU
            3'd3:    result = prod_uu[63:32];    // MULHU
            default: result = 32'd0;
        endcase
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_btb.v
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
//  from: rtl/core/riscv_core.v
// --------------------------------------------------------------------------
//=============================================================================
//  riscv_core.v : RV32I 五级流水线处理器内核
//  IF -> ID -> EX -> MEM -> WB
//  - 全转发 + load-use 停顿
//  - 分支/跳转在 EX 级解决（静态预测不跳转，跳转时清空 2 条指令）
//  - CSR / 异常 / 机器定时器中断 / mret
//  - 指令与数据接口均为组合读（便于映射 LUTRAM；后续可替换为带 I/D Cache
//    的同步 BRAM 版本）
//=============================================================================

module riscv_core #(
    parameter [31:0] RESET_VEC  = 32'h0000_0000,
    parameter [31:0] MTVEC_INIT = 32'h0000_0040
)(
    input  wire        clk,
    input  wire        rst_n,

    //------------------- 指令取指接口 ---------------------------------------
    output wire [31:0] imem_addr,
    output wire        imem_req,
    input  wire [31:0] imem_rdata,

    //------------------- 数据访存接口 ---------------------------------------
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_be,
    output wire        dmem_we,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,

    //------------------- 中断 -----------------------------------------------
    input  wire        irq_timer,
    input  wire        irq_ext,

    //------------------- Cache 停顿 / 冲刷 -----------------------------------
    input  wire        if_stall,       // I-Cache 缺失：冻结取指
    input  wire        mem_stall,      // D-Cache 缺失：冻结整条流水线

    //------------------- 提交监视（调试/覆盖率） -----------------------------
    output wire        commit_valid,
    output wire [31:0] commit_pc,
    output wire [31:0] commit_instr
);

    //=========================================================================
    //  1. 流水寄存器声明
    //=========================================================================
    //-------------------------- PC / IF/ID -----------------------------------
    reg  [31:0] pc;
    reg         ifid_valid;
    reg  [31:0] ifid_pc;
    reg  [31:0] ifid_instr;
    reg         ifid_pred_taken;
    reg  [31:0] ifid_pred_target;

    //-------------------------- ID/EX ----------------------------------------
    reg         idex_valid;
    reg  [31:0] idex_pc, idex_instr;
    reg  [31:0] idex_rs1_data, idex_rs2_data;
    reg  [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg         idex_use_rs1, idex_use_rs2;
    reg  [31:0] idex_imm;
    reg         idex_alu_a_pc, idex_alu_b_imm;
    reg  [3:0]  idex_alu_op;
    reg         idex_reg_write, idex_mem_read, idex_mem_write;
    reg  [1:0]  idex_wb_sel;
    reg  [2:0]  idex_branch_type;
    reg  [1:0]  idex_jump_type;
    reg  [1:0]  idex_csr_op;
    reg         idex_csr_imm;
    reg  [11:0] idex_csr_addr;
    reg         idex_exc_valid;
    reg  [3:0]  idex_exc_cause;
    reg  [31:0] idex_exc_tval;
    reg         idex_is_mret;
    reg         idex_is_muldiv;
    reg  [2:0]  idex_muldiv_op;
    reg         idex_pred_taken;
    reg  [31:0] idex_pred_target;

    //-------------------------- EX/MEM ---------------------------------------
    reg         exmem_valid;
    reg  [31:0] exmem_pc, exmem_instr;
    reg  [31:0] exmem_alu_result;
    reg  [31:0] exmem_store_data;
    reg  [31:0] exmem_rs1_data;
    reg         exmem_is_muldiv;
    reg  [2:0]  exmem_muldiv_op;
    reg  [4:0]  exmem_rd;
    reg         exmem_reg_write, exmem_mem_read, exmem_mem_write;
    reg  [1:0]  exmem_wb_sel;
    reg  [2:0]  exmem_funct3;
    reg         exmem_csr_we;
    reg  [1:0]  exmem_csr_op;
    reg  [11:0] exmem_csr_addr;
    reg  [31:0] exmem_csr_wdata;
    reg  [31:0] exmem_csr_rdata;
    reg         exmem_exc_valid;
    reg  [3:0]  exmem_exc_cause;
    reg  [31:0] exmem_exc_tval;
    reg         exmem_is_mret;

    //-------------------------- MEM/WB ---------------------------------------
    reg         memwb_valid;
    reg  [31:0] memwb_pc, memwb_instr;
    reg  [31:0] memwb_wb_data;
    reg  [4:0]  memwb_rd;
    reg         memwb_reg_write;

    //=========================================================================
    //  2. 全局连线
    //=========================================================================
    wire [31:0] pc_plus4 = pc + 32'd4;

    assign imem_addr = pc;
    assign imem_req  = 1'b1;

    // BTB 查询结果（IF 级）
    wire        btb_pred_taken;
    wire [31:0] btb_pred_target;

    // MEM 级异常/中断（提前声明，供 EX 级除法器中止使用）
    wire        trap_take;
    wire        mret_take;

    //=========================================================================
    //  3. 取指 + 译码 + 寄存器堆
    //=========================================================================
    wire        dec_illegal;
    wire [4:0]  dec_rs1, dec_rs2, dec_rd;
    wire        dec_use_rs1, dec_use_rs2;
    wire [31:0] dec_imm;
    wire        dec_reg_write, dec_mem_read, dec_mem_write;
    wire        dec_alu_a_pc, dec_alu_b_imm;
    wire        dec_is_muldiv;
    wire [2:0]  dec_muldiv_op;
    wire [3:0]  dec_alu_op;
    wire [1:0]  dec_wb_sel;
    wire [2:0]  dec_branch_type;
    wire [1:0]  dec_jump_type;
    wire [1:0]  dec_csr_op;
    wire        dec_csr_imm;
    wire [11:0] dec_csr_addr;
    wire        dec_ecall, dec_ebreak, dec_mret;

    riscv_decoder u_decoder (
        .instr        (ifid_instr),
        .illegal      (dec_illegal),
        .rs1          (dec_rs1),
        .rs2          (dec_rs2),
        .rd           (dec_rd),
        .use_rs1      (dec_use_rs1),
        .use_rs2      (dec_use_rs2),
        .imm          (dec_imm),
        .is_muldiv    (dec_is_muldiv),
        .muldiv_op    (dec_muldiv_op),
        .reg_write    (dec_reg_write),
        .mem_read     (dec_mem_read),
        .mem_write    (dec_mem_write),
        .alu_src_a_pc (dec_alu_a_pc),
        .alu_src_b_imm(dec_alu_b_imm),
        .alu_op       (dec_alu_op),
        .wb_sel       (dec_wb_sel),
        .branch_type  (dec_branch_type),
        .jump_type    (dec_jump_type),
        .csr_op       (dec_csr_op),
        .csr_imm      (dec_csr_imm),
        .csr_addr     (dec_csr_addr),
        .is_ecall     (dec_ecall),
        .is_ebreak    (dec_ebreak),
        .is_mret      (dec_mret)
    );

    wire [31:0] rf_rs1_data, rf_rs2_data;
    wire        rf_we;
    wire [4:0]  rf_waddr;
    wire [31:0] rf_wdata;

    riscv_regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (dec_rs1),
        .rs1_data (rf_rs1_data),
        .rs2_addr (dec_rs2),
        .rs2_data (rf_rs2_data),
        .we       (rf_we),
        .rd_addr  (rf_waddr),
        .rd_data  (rf_wdata)
    );

    //-------------------------------------------------------------------------
    // WB -> ID 旁路：寄存器堆同拍写读时，ID 级需要看到刚写回的数据
    // （相距 3 条指令的 RAW 冒险）
    //-------------------------------------------------------------------------
    wire [31:0] id_rs1_value = (rf_we && (rf_waddr == dec_rs1)) ? rf_wdata : rf_rs1_data;
    wire [31:0] id_rs2_value = (rf_we && (rf_waddr == dec_rs2)) ? rf_wdata : rf_rs2_data;

    //=========================================================================
    //  4. 执行级组合逻辑：转发 / ALU / 分支 / 例外
    //=========================================================================
    wire [1:0]  fwd_a, fwd_b;
    wire        load_use_stall, csr_stall;
    wire        id_is_csr = (dec_csr_op != `CSR_NONE);

    wire [31:0] exmem_fwd_data = (exmem_wb_sel == `WB_PC4) ? (exmem_pc + 32'd4) :
                                 (exmem_wb_sel == `WB_CSR) ? exmem_csr_rdata :
                                                              exmem_alu_result;

    wire [31:0] ex_src1 = (fwd_a == 2'b10) ? exmem_fwd_data :
                          (fwd_a == 2'b01) ? memwb_wb_data  :
                                             idex_rs1_data;
    wire [31:0] ex_src2 = (fwd_b == 2'b10) ? exmem_fwd_data :
                          (fwd_b == 2'b01) ? memwb_wb_data  :
                                             idex_rs2_data;

    wire [31:0] ex_alu_a = idex_alu_a_pc  ? idex_pc : ex_src1;
    wire [31:0] ex_alu_b = idex_alu_b_imm ? idex_imm : ex_src2;
    wire [31:0] ex_alu_y;

    riscv_alu u_alu (
        .a  (ex_alu_a),
        .b  (ex_alu_b),
        .op (idex_alu_op),
        .y  (ex_alu_y)
    );

    //------------------------- M 扩展：除法（32 拍） -------------------------
    wire        div_start;
    wire        div_busy, div_done;
    wire [31:0] div_result;

    riscv_divider u_divider (
        .clk   (clk),
        .rst_n (rst_n),
        .flush (trap_take || mret_take),
        .start (div_start),
        .op    (idex_muldiv_op),
        .a     (ex_src1),
        .b     (ex_src2),
        .result(div_result),
        .busy  (div_busy),
        .done  (div_done)
    );

    wire ex_is_div   = idex_is_muldiv && idex_muldiv_op[2];
    wire ex_is_mul   = idex_is_muldiv && !idex_muldiv_op[2];
    wire div_freeze  = idex_valid && ex_is_div && !div_done;

    assign div_start = idex_valid && ex_is_div && !div_busy && !div_done;

    wire [31:0] ex_result = (idex_is_muldiv && idex_muldiv_op[2]) ? div_result : ex_alu_y;

    // 除法进行中冻结整条流水线
    wire pipe_freeze = mem_stall || div_freeze;

    reg br_taken;
    always @(*) begin
        case (idex_branch_type)
            `BR_EQ : br_taken = (ex_src1 == ex_src2);
            `BR_NE : br_taken = (ex_src1 != ex_src2);
            `BR_LT : br_taken = ($signed(ex_src1) <  $signed(ex_src2));
            `BR_GE : br_taken = ($signed(ex_src1) >= $signed(ex_src2));
            `BR_LTU: br_taken = (ex_src1 <  ex_src2);
            `BR_GEU: br_taken = (ex_src1 >= ex_src2);
            default: br_taken = 1'b0;
        endcase
    end

    wire        ex_is_jump   = (idex_jump_type != `JUMP_NONE);
    wire        ex_is_branch = (idex_branch_type != `BR_NONE);
    wire        ex_is_ctrl   = ex_is_jump || ex_is_branch;

    wire [31:0] ex_jump_target = (idex_jump_type == `JUMP_JALR) ?
                                 ((ex_src1 + idex_imm) & 32'hFFFF_FFFE) :
                                 (idex_pc + idex_imm);

    // 实际方向 / 目标
    wire        ex_actual_taken  = ex_is_jump || (ex_is_branch && br_taken);
    wire [31:0] ex_actual_target = ex_is_jump ? ex_jump_target : (idex_pc + idex_imm);

    // 该指令被取指时 BTB 给出的预测
    wire        ex_pred_taken  = idex_pred_taken;
    wire [31:0] ex_pred_target = idex_pred_target;

    // 预测失败：方向不符 / 目标不符 / 预测跳转但并非控制指令
    wire        ex_mispredict = idex_valid &&
                                (ex_is_ctrl ?
                                 ((ex_actual_taken != ex_pred_taken) ||
                                  (ex_actual_taken && (ex_actual_target != ex_pred_target)))
                                 : ex_pred_taken);

    wire        ex_target_misaligned = idex_valid && ex_actual_taken &&
                                       (ex_actual_target[1:0] != 2'b00);

    // 非对齐访存：LW/SW 要求 addr[1:0]==0，LH/LHU/SH 要求 addr[0]==0
    wire [2:0]  ex_funct3   = idex_instr[14:12];
    wire [1:0]  ex_addr_lo  = ex_alu_y[1:0];
    wire        ex_mis_ldst = (idex_mem_read || idex_mem_write) &&
                              (((ex_funct3 == 3'b010) && (ex_addr_lo != 2'b00)) ||
                               ((ex_funct3 == 3'b001) && (ex_addr_lo[0] != 1'b0)));
    wire [3:0]  ex_mis_cause = idex_mem_write ? `CAUSE_STORE_MISALIGN
                                              : `CAUSE_LOAD_MISALIGN;

    wire        ex_exc_valid = idex_valid && (idex_exc_valid || ex_target_misaligned || ex_mis_ldst);
    wire [3:0]  ex_exc_cause = idex_exc_valid        ? idex_exc_cause :
                               ex_target_misaligned  ? `CAUSE_INSTR_MISALIGN :
                                                       ex_mis_cause;
    wire [31:0] ex_exc_tval  = idex_exc_valid        ? idex_exc_tval :
                               ex_target_misaligned  ? ex_actual_target :
                                                       ex_alu_y;

    wire        ex_redirect_ok = ex_mispredict && !ex_exc_valid;
    wire [31:0] ex_target = ex_actual_taken ? ex_actual_target : (idex_pc + 32'd4);

    wire [31:0] ex_csr_wdata = idex_csr_imm ? {27'd0, idex_rs1} : ex_src1;

    //=========================================================================
    //  5. 访存级：LSU / 异常 / 中断 / CSR 提交
    //=========================================================================
    wire [31:0] mem_load_data;
    wire [3:0]  mem_be;
    wire [31:0] mem_wdata;

    riscv_lsu u_lsu (
        .addr_lo   (exmem_alu_result[1:0]),
        .funct3    (exmem_funct3),
        .store_data(exmem_store_data),
        .rdata     (dmem_rdata),
        .be        (mem_be),
        .wdata     (mem_wdata),
        .load_data (mem_load_data)
    );

    wire        csr_irq_pending;
    wire [3:0]  csr_irq_cause;
    wire        mem_exc     = exmem_valid && exmem_exc_valid;
    wire        trap_is_irq = !mem_exc && csr_irq_pending;
    wire        irq_take    = exmem_valid && trap_is_irq;
    assign trap_take = mem_exc || irq_take;
    assign mret_take = exmem_valid && exmem_is_mret && !trap_take;

    wire [3:0]  trap_cause = mem_exc ? exmem_exc_cause : csr_irq_cause;
    wire [31:0] trap_tval  = mem_exc ? exmem_exc_tval  : 32'd0;

    wire        mem_csr_we = exmem_valid && exmem_csr_we && !trap_take && !pipe_freeze;

    assign dmem_addr  = exmem_alu_result;
    assign dmem_wdata = mem_wdata;
    assign dmem_be    = mem_be;
    assign dmem_we    = exmem_valid && exmem_mem_write && !trap_take && !pipe_freeze;
    assign dmem_re    = exmem_valid && exmem_mem_read && !exmem_exc_valid;

    //=========================================================================
    //  6. CSR 寄存器组
    //=========================================================================
    wire [31:0] csr_rdata;
    wire [31:0] csr_mtvec, csr_mepc;

    riscv_csr #(.MTVEC_INIT(MTVEC_INIT)) u_csr (
        .clk        (clk),
        .rst_n      (rst_n),
        .raddr      (idex_csr_addr),
        .rdata      (csr_rdata),
        .we         (mem_csr_we),
        .waddr      (exmem_csr_addr),
        .wop        (exmem_csr_op),
        .wdata      (exmem_csr_wdata),
        .trap       (trap_take),
        .trap_is_irq(trap_is_irq),
        .trap_cause (trap_cause),
        .trap_tval  (trap_tval),
        .trap_epc   (exmem_pc),
        .mret       (mret_take),
        .irq_timer  (irq_timer),
        .irq_ext    (irq_ext),
        .irq_pending(csr_irq_pending),
        .irq_cause  (csr_irq_cause),
        .mtvec_o    (csr_mtvec),
        .mepc_o     (csr_mepc),
        .retire     (memwb_valid && !pipe_freeze)
    );

    //=========================================================================
    //  6b. BTB + 两位饱和计数器
    //=========================================================================
    wire btb_upd_valid = idex_valid && ex_is_ctrl && !ex_exc_valid &&
                         !trap_take && !mret_take;

    riscv_btb #(.ENTRIES(64)) u_btb (
        .clk        (clk),
        .rst_n      (rst_n),
        .lookup_pc  (pc),
        .pred_taken (btb_pred_taken),
        .pred_target(btb_pred_target),
        .upd_valid  (btb_upd_valid),
        .upd_pc     (idex_pc),
        .upd_taken  (ex_actual_taken),
        .upd_target (ex_actual_target)
    );

    //=========================================================================
    //  7. 写回 / 提交
    //=========================================================================
    assign rf_we    = memwb_valid && memwb_reg_write && (memwb_rd != 5'd0);
    assign rf_waddr = memwb_rd;
    assign rf_wdata = memwb_wb_data;

    assign commit_valid = memwb_valid && !pipe_freeze;
    assign commit_pc    = memwb_pc;
    assign commit_instr = memwb_instr;

    //------------------------- MEM 级乘法（操作数已寄存） --------------------
    wire [31:0] mem_mul_result;
    wire        exmem_is_mul = exmem_is_muldiv && !exmem_muldiv_op[2];

    riscv_mul u_mul (
        .op    (exmem_muldiv_op),
        .a     (exmem_rs1_data),
        .b     (exmem_store_data),
        .result(mem_mul_result)
    );

    wire [31:0] mem_alu_or_mul = exmem_is_mul ? mem_mul_result : exmem_alu_result;

    wire [31:0] mem_wb_data_next = (exmem_wb_sel == `WB_MEM) ? mem_load_data :
                                   (exmem_wb_sel == `WB_PC4) ? (exmem_pc + 32'd4) :
                                   (exmem_wb_sel == `WB_CSR) ? exmem_csr_rdata :
                                                              mem_alu_or_mul;

    //=========================================================================
    //  8. 冒险单元
    //=========================================================================
    riscv_hazard u_hazard (
        .id_rs1        (dec_rs1),
        .id_rs2        (dec_rs2),
        .id_use_rs1    (dec_use_rs1),
        .id_use_rs2    (dec_use_rs2),
        .id_valid      (ifid_valid),
        .ex_valid      (idex_valid),
        .ex_rd         (idex_rd),
        .ex_reg_write  (idex_reg_write),
        .ex_mem_read   (idex_mem_read || ex_is_mul),
        .ex_use_rs1    (idex_use_rs1),
        .ex_use_rs2    (idex_use_rs2),
        .ex_rs1        (idex_rs1),
        .ex_rs2        (idex_rs2),
        .mem_valid     (exmem_valid),
        .mem_rd        (exmem_rd),
        .mem_reg_write (exmem_reg_write),
        .mem_mem_read  (exmem_mem_read || exmem_is_mul),
        .wb_valid      (memwb_valid),
        .wb_rd         (memwb_rd),
        .wb_reg_write  (memwb_reg_write),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b),
        .load_use_stall(load_use_stall),
        .id_is_csr     (id_is_csr),
        .id_csr_addr   (dec_csr_addr),
        .ex_csr_we     (idex_valid && (idex_csr_op != `CSR_NONE)),
        .ex_csr_addr   (idex_csr_addr),
        .csr_stall     (csr_stall)
    );

    wire fetch_hold       = if_stall && !pipe_freeze;
    wire id_stall         = (load_use_stall || csr_stall) && ifid_valid && !pipe_freeze;
    wire ex_redirect_ok_f = ex_redirect_ok && !pipe_freeze;


`ifdef TRAPDBG
    always @(posedge clk) begin
        if (rst_n && trap_take)
            $display("[trap] pc=%08h cause=%0d tval=%08h irq=%b", exmem_pc, trap_cause, trap_tval, trap_is_irq);
    end
`endif

    //=========================================================================
    //  9. 时序：PC 与流水寄存器更新
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pc            <= RESET_VEC;
            ifid_valid    <= 1'b0;
            ifid_pc       <= 32'd0;
            ifid_instr    <= 32'h0000_0013;
            ifid_pred_taken  <= 1'b0;
            ifid_pred_target <= 32'd0;

            idex_valid    <= 1'b0;
            idex_pc       <= 32'd0;
            idex_instr    <= 32'h0000_0013;
            idex_rs1_data <= 32'd0;
            idex_rs2_data <= 32'd0;
            idex_rs1      <= 5'd0;
            idex_rs2      <= 5'd0;
            idex_rd       <= 5'd0;
            idex_use_rs1  <= 1'b0;
            idex_use_rs2  <= 1'b0;
            idex_imm      <= 32'd0;
            idex_alu_a_pc <= 1'b0;
            idex_alu_b_imm<= 1'b0;
            idex_alu_op   <= `ALU_ADD;
            idex_reg_write<= 1'b0;
            idex_mem_read <= 1'b0;
            idex_mem_write<= 1'b0;
            idex_wb_sel   <= `WB_ALU;
            idex_branch_type <= `BR_NONE;
            idex_jump_type   <= `JUMP_NONE;
            idex_csr_op   <= `CSR_NONE;
            idex_csr_imm  <= 1'b0;
            idex_csr_addr <= 12'd0;
            idex_exc_valid<= 1'b0;
            idex_exc_cause<= 4'd0;
            idex_exc_tval <= 32'd0;
            idex_is_mret  <= 1'b0;
            idex_is_muldiv<= 1'b0;
            idex_muldiv_op<= 3'd0;
            idex_pred_taken  <= 1'b0;
            idex_pred_target <= 32'd0;

            exmem_valid   <= 1'b0;
            exmem_pc      <= 32'd0;
            exmem_instr   <= 32'h0000_0013;
            exmem_alu_result <= 32'd0;
            exmem_store_data <= 32'd0;
            exmem_rs1_data   <= 32'd0;
            exmem_is_muldiv  <= 1'b0;
            exmem_muldiv_op  <= 3'd0;
            exmem_rd      <= 5'd0;
            exmem_reg_write <= 1'b0;
            exmem_mem_read  <= 1'b0;
            exmem_mem_write <= 1'b0;
            exmem_wb_sel  <= `WB_ALU;
            exmem_funct3  <= 3'd0;
            exmem_csr_we  <= 1'b0;
            exmem_csr_op  <= `CSR_NONE;
            exmem_csr_addr<= 12'd0;
            exmem_csr_wdata <= 32'd0;
            exmem_csr_rdata <= 32'd0;
            exmem_exc_valid <= 1'b0;
            exmem_exc_cause <= 4'd0;
            exmem_exc_tval  <= 32'd0;
            exmem_is_mret   <= 1'b0;

            memwb_valid   <= 1'b0;
            memwb_pc      <= 32'd0;
            memwb_instr   <= 32'h0000_0013;
            memwb_wb_data <= 32'd0;
            memwb_rd      <= 5'd0;
            memwb_reg_write <= 1'b0;
        end else begin
            //------------------------- PC ----------------------------------
            if (trap_take)
                pc <= csr_mtvec;
            else if (mret_take)
                pc <= csr_mepc;
            else if (ex_redirect_ok_f)
                pc <= ex_target;
            else if (pipe_freeze || id_stall || fetch_hold)
                pc <= pc;
            else
                pc <= btb_pred_taken ? btb_pred_target : pc_plus4;

            //------------------------- IF/ID --------------------------------
            if (trap_take || mret_take || ex_redirect_ok_f) begin
                ifid_valid <= 1'b0;
            end else if (pipe_freeze || id_stall) begin
                ifid_valid <= ifid_valid;
            end else if (fetch_hold) begin
                ifid_valid <= 1'b0;              // 取指缺失：插入气泡，PC 保持
            end else begin
                ifid_valid <= 1'b1;
                ifid_pc    <= pc;
                ifid_instr <= imem_rdata;
                ifid_pred_taken  <= btb_pred_taken;
                ifid_pred_target <= btb_pred_target;
            end

            //------------------------- ID/EX ---------------------------------
            if (trap_take || mret_take || ex_redirect_ok_f || id_stall) begin
                idex_valid <= 1'b0;
            end else if (pipe_freeze) begin
                // 保持
            end else begin
                idex_valid    <= ifid_valid;
                idex_pc       <= ifid_pc;
                idex_instr    <= ifid_instr;
                idex_rs1_data <= id_rs1_value;
                idex_rs2_data <= id_rs2_value;
                idex_rs1      <= dec_rs1;
                idex_rs2      <= dec_rs2;
                idex_rd       <= dec_rd;
                idex_use_rs1  <= dec_use_rs1;
                idex_use_rs2  <= dec_use_rs2;
                idex_imm      <= dec_imm;
                idex_alu_a_pc <= dec_alu_a_pc;
                idex_alu_b_imm<= dec_alu_b_imm;
                idex_alu_op   <= dec_alu_op;
                idex_reg_write<= dec_reg_write;
                idex_mem_read <= dec_mem_read;
                idex_mem_write<= dec_mem_write;
                idex_wb_sel   <= dec_wb_sel;
                idex_branch_type <= dec_branch_type;
                idex_jump_type   <= dec_jump_type;
                idex_csr_op   <= dec_csr_op;
                idex_csr_imm  <= dec_csr_imm;
                idex_csr_addr <= dec_csr_addr;
                idex_exc_valid<= ifid_valid && (dec_illegal || dec_ecall || dec_ebreak);
                idex_exc_cause<= dec_ecall  ? `CAUSE_ECALL_M :
                                 dec_ebreak ? `CAUSE_BREAKPOINT :
                                              `CAUSE_ILLEGAL_INSTR;
                idex_exc_tval <= (dec_ecall || dec_ebreak) ? 32'd0 : ifid_instr;
                idex_is_mret  <= dec_mret;
                idex_is_muldiv<= dec_is_muldiv;
                idex_muldiv_op<= dec_muldiv_op;
                idex_pred_taken  <= ifid_pred_taken;
                idex_pred_target <= ifid_pred_target;
            end

            //------------------------- EX/MEM --------------------------------
            if (trap_take || mret_take) begin
                exmem_valid <= 1'b0;
            end else if (pipe_freeze) begin
                // 保持
            end else begin
                exmem_valid      <= idex_valid;
                exmem_pc         <= idex_pc;
                exmem_instr      <= idex_instr;
                exmem_alu_result <= ex_result;
                exmem_store_data <= ex_src2;
                exmem_rs1_data   <= ex_src1;
                exmem_is_muldiv  <= idex_is_muldiv;
                exmem_muldiv_op  <= idex_muldiv_op;
                exmem_rd         <= idex_rd;
                exmem_reg_write  <= idex_reg_write;
                exmem_mem_read   <= idex_mem_read;
                exmem_mem_write  <= idex_mem_write;
                exmem_wb_sel     <= idex_wb_sel;
                exmem_funct3     <= idex_instr[14:12];
                exmem_csr_we     <= (idex_csr_op != `CSR_NONE) && idex_valid && !ex_exc_valid;
                exmem_csr_op     <= idex_csr_op;
                exmem_csr_addr   <= idex_csr_addr;
                exmem_csr_wdata  <= ex_csr_wdata;
                exmem_csr_rdata  <= csr_rdata;
                exmem_exc_valid  <= ex_exc_valid;
                exmem_exc_cause  <= ex_exc_cause;
                exmem_exc_tval   <= ex_exc_tval;
                exmem_is_mret    <= idex_is_mret;
            end

            //------------------------- MEM/WB --------------------------------
            if (pipe_freeze) begin
                // 保持
            end else begin
                memwb_valid     <= exmem_valid && !trap_take;
                memwb_pc        <= exmem_pc;
                memwb_instr     <= exmem_instr;
                memwb_wb_data   <= mem_wb_data_next;
                memwb_rd        <= exmem_rd;
                memwb_reg_write <= exmem_reg_write;
            end
        end
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/mem/imem.v
// --------------------------------------------------------------------------
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

        initial begin
        mem[0] = 128'h020302630002c3030002829310000297;
        mem[1] = 128'h001e7e130043ae0300038393200003b7;
        mem[2] = 128'hfddff06f001282930063a023fe0e1ce3;
        mem[3] = 128'h0062a0230010031300028293300002b7;
        mem[4] = 128'h0000000000000000000000000000006f;
    end

    always @(posedge clk) begin
        if (re)
            rdata <= mem[addr[15:4]];
        rvalid <= re;
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/mem/dmem.v
// --------------------------------------------------------------------------
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

        initial begin
        mem[0] = 128'h4932335652206d6f7266206f6c6c6548;
        mem[1] = 128'h000000000000006e5c725c21436f5320;
    end

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

// --------------------------------------------------------------------------
//  from: rtl/mem/icache.v
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
//  from: rtl/mem/dcache.v
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
//  from: rtl/ai/ai_accel.v
// --------------------------------------------------------------------------
//=============================================================================
//  ai_accel.v : INT8 matrix-vector accelerator (memory mapped)
//
//  Register space 0x2000_4000  (reg_idx = addr[7:2])
//    0  CTRL   W: bit0=start, bit1=clear done    R: bit0=busy, bit1=done
//    1  OP     W: 0=FC, 1=RELU, 2=ARGMAX
//    2  K      inner length (FC)
//    3  N      element count (RELU / ARGMAX)
//    4  WA     weight byte offset (4-byte aligned, K x 4 INT8, row major)
//    5  XA     input byte offset (K INT8)
//    6  YA     output byte offset (N INT32)
//    8  CYC    R: cycles of last op
//    9  ARG    R: ARGMAX result
//
//  Buffer 0x2000_8000 - 0x2000_9FFF (8 KB, 2048 x 32)
//
//  FC     : y[j] = sum_k W[k][j] * x[k], 4 outputs per run, INT8 x INT8 -> INT32
//           (bias is folded into an extra row of W with x set to 1)
//  RELU   : in-place ReLU on N INT32 words at YA
//  ARGMAX : index of max over N INT32 words at YA
//=============================================================================
module ai_accel #(
    parameter LANES = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cs_reg,
    input  wire        cs_buf,
    input  wire [7:0]  reg_idx,
    input  wire [10:0] buf_idx,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        busy,
    output wire        done
);

    //--------------------- local buffer --------------------------------------
    reg [31:0] abuf [0:2047];

    reg  [31:0] cfg_op, cfg_k, cfg_n, cfg_wa, cfg_xa, cfg_ya;
    reg  [31:0] cyc_cnt, arg_val;
    reg         op_busy, done_r;

    assign busy = op_busy;
    assign done = done_r;

    //--------------------- states --------------------------------------------
    localparam S_IDLE = 3'd0;
    localparam S_FC   = 3'd1;
    localparam S_WR   = 3'd2;
    localparam S_RELU = 3'd3;
    localparam S_ARG  = 3'd4;
    localparam S_FIN  = 3'd5;

    localparam OP_FC     = 4'd0;
    localparam OP_RELU   = 4'd1;
    localparam OP_ARGMAX = 4'd2;

    reg  [2:0]  state;
    reg  [31:0] k_cnt, wr_cnt, elem_cnt;
    reg signed [63:0] acc0, acc1, acc2, acc3;
    reg  [31:0] max_val, max_idx;

    //--------------------- engine addressing ---------------------------------
    wire [10:0] fc_w_addr = cfg_wa[12:2] + k_cnt[10:0];
    wire [10:0] fc_x_addr = (cfg_xa + k_cnt) >> 2;
    wire [1:0]  fc_x_lane = (cfg_xa + k_cnt) & 3;
    wire [10:0] wr_addr   = cfg_ya[12:2] + wr_cnt[10:0];
    wire [10:0] el_addr   = cfg_ya[12:2] + elem_cnt[10:0];

    reg  [10:0] eng_addr;
    always @(*) begin
        case (state)
            S_FC:          eng_addr = fc_w_addr;
            S_WR:          eng_addr = wr_addr;
            S_RELU, S_ARG: eng_addr = el_addr;
            default:       eng_addr = buf_idx;
        endcase
    end

    wire [10:0] a_addr = op_busy ? eng_addr : buf_idx;
    wire        eng_wr = op_busy && ((state == S_WR) || (state == S_RELU));
    wire        a_we   = eng_wr || (!op_busy && cs_buf && we);

    wire [31:0] port_a_rdata = abuf[a_addr];
    wire [31:0] port_b_rdata = abuf[fc_x_addr];

    wire signed [63:0] w0 = {{32{port_a_rdata[7]}},  port_a_rdata[7:0]};
    wire signed [63:0] w1 = {{32{port_a_rdata[15]}}, port_a_rdata[15:8]};
    wire signed [63:0] w2 = {{32{port_a_rdata[23]}}, port_a_rdata[23:16]};
    wire signed [63:0] w3 = {{32{port_a_rdata[31]}}, port_a_rdata[31:24]};

    wire [7:0] xb_byte = port_b_rdata[{fc_x_lane, 3'b000} +: 8];
    wire signed [63:0] xb = {{56{xb_byte[7]}}, xb_byte};

    wire signed [63:0] p0 = w0 * xb;
    wire signed [63:0] p1 = w1 * xb;
    wire signed [63:0] p2 = w2 * xb;
    wire signed [63:0] p3 = w3 * xb;

    wire [31:0] acc_sel = (wr_cnt == 32'd0) ? acc0[31:0] :
                          (wr_cnt == 32'd1) ? acc1[31:0] :
                          (wr_cnt == 32'd2) ? acc2[31:0] : acc3[31:0];

    wire [31:0] a_wdata = eng_wr ? ((state == S_RELU)
                                     ? (port_a_rdata[31] ? 32'd0 : port_a_rdata)
                                     : acc_sel)
                                  : wdata;
    wire [3:0]  a_be = eng_wr ? 4'b1111 : be;

    always @(posedge clk) begin
        if (a_we) begin
            if (a_be[0]) abuf[a_addr][7:0]   <= a_wdata[7:0];
            if (a_be[1]) abuf[a_addr][15:8]  <= a_wdata[15:8];
            if (a_be[2]) abuf[a_addr][23:16] <= a_wdata[23:16];
            if (a_be[3]) abuf[a_addr][31:24] <= a_wdata[31:24];
        end
    end

    //--------------------- register read ------------------------------------
    always @(*) begin
        if (cs_buf)
            rdata = port_a_rdata;
        else if (cs_reg) begin
            case (reg_idx[3:0])
                4'd0:    rdata = {30'd0, done_r, op_busy};
                4'd1:    rdata = cfg_op;
                4'd2:    rdata = cfg_k;
                4'd3:    rdata = cfg_n;
                4'd4:    rdata = cfg_wa;
                4'd5:    rdata = cfg_xa;
                4'd6:    rdata = cfg_ya;
                4'd8:    rdata = cyc_cnt;
                4'd9:    rdata = arg_val;
                default: rdata = 32'd0;
            endcase
        end else
            rdata = 32'd0;
    end

`ifdef AIDBG
    always @(posedge clk) begin
        if (op_busy && (state == S_FC) && (k_cnt < 32'd4))
            $display("[fc] k=%0d w=%08h xr=%08h b0=%08h b1568=%08h", k_cnt, port_a_rdata, port_b_rdata, abuf[0], abuf[1568]);
    end
`endif

    //--------------------- control FSM --------------------------------------
    wire start = cs_reg && we && (reg_idx[3:0] == 4'd0) && wdata[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            op_busy  <= 1'b0;
            done_r   <= 1'b0;
            k_cnt    <= 32'd0;
            wr_cnt   <= 32'd0;
            elem_cnt <= 32'd0;
            acc0     <= 64'sd0;
            acc1     <= 64'sd0;
            acc2     <= 64'sd0;
            acc3     <= 64'sd0;
            cyc_cnt  <= 32'd0;
            arg_val  <= 32'd0;
            max_val  <= 32'h8000_0000;
            max_idx  <= 32'd0;
            cfg_op   <= 32'd0;
            cfg_k    <= 32'd0;
            cfg_n    <= 32'd0;
            cfg_wa   <= 32'd0;
            cfg_xa   <= 32'd0;
            cfg_ya   <= 32'd0;
        end else begin
            if (cs_reg && we) begin
                case (reg_idx[3:0])
                    4'd0: if (wdata[1]) done_r <= 1'b0;
                    4'd1: cfg_op <= wdata;
                    4'd2: cfg_k  <= wdata;
                    4'd3: cfg_n  <= wdata;
                    4'd4: cfg_wa <= wdata;
                    4'd5: cfg_xa <= wdata;
                    4'd6: cfg_ya <= wdata;
                    default: ;
                endcase
            end

            case (state)
                S_IDLE: begin
                    if (start) begin
                        op_busy  <= 1'b1;
                        done_r   <= 1'b0;
                        cyc_cnt  <= 32'd0;
                        k_cnt    <= 32'd0;
                        wr_cnt   <= 32'd0;
                        elem_cnt <= 32'd0;
                        acc0 <= 64'sd0;
                        acc1 <= 64'sd0;
                        acc2 <= 64'sd0;
                        acc3 <= 64'sd0;
                        max_val <= 32'h8000_0000;
                        max_idx <= 32'd0;
                        case (cfg_op[3:0])
                            OP_FC:     state <= S_FC;
                            OP_RELU:   state <= S_RELU;
                            OP_ARGMAX: state <= S_ARG;
                            default:   state <= S_FIN;
                        endcase
                    end
                end

                S_FC: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    acc0 <= acc0 + p0;
                    acc1 <= acc1 + p1;
                    acc2 <= acc2 + p2;
                    acc3 <= acc3 + p3;
                    if (k_cnt + 32'd1 >= cfg_k)
                        state <= S_WR;
                    else
                        k_cnt <= k_cnt + 32'd1;
                end

                S_WR: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if (wr_cnt == 32'd3)
                        state <= S_FIN;
                    else
                        wr_cnt <= wr_cnt + 32'd1;
                end

                S_RELU: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if (elem_cnt + 32'd1 >= cfg_n)
                        state <= S_FIN;
                    else
                        elem_cnt <= elem_cnt + 32'd1;
                end

                S_ARG: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if ($signed(port_a_rdata) > $signed(max_val)) begin
                        max_val <= port_a_rdata;
                        max_idx <= elem_cnt;
                    end
                    if (elem_cnt + 32'd1 >= cfg_n) begin
                        arg_val <= ($signed(port_a_rdata) > $signed(max_val)) ? elem_cnt : max_idx;
                        state   <= S_FIN;
                    end else begin
                        elem_cnt <= elem_cnt + 32'd1;
                    end
                end

                S_FIN: begin
                    op_busy <= 1'b0;
                    done_r  <= 1'b1;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/periph/uart_tx.v
// --------------------------------------------------------------------------
//=============================================================================
//  uart_tx.v : 8N1 串口发送器
//=============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 868          // 100 MHz / 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output wire       busy
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (start) begin
                        shreg <= data;
                        state <= S_START;
                    end
                end
                S_START: begin
                    tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                S_DATA: begin
                    tx <= shreg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                S_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/periph/uart_rx.v
// --------------------------------------------------------------------------
//=============================================================================
//  uart_rx.v : 8N1 串口接收器（起始位中点采样）
//=============================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'd0;
            data    <= 8'd0;
            valid   <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (!rx)
                        state <= S_START;
                end
                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        clk_cnt <= 16'd0;
                        if (!rx) state <= S_DATA;
                        else     state <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt    <= 16'd0;
                        shreg[bit_idx] <= rx;
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        data    <= shreg;
                        valid   <= 1'b1;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/periph/gpio.v
// --------------------------------------------------------------------------
//=============================================================================
//  gpio.v : 通用 GPIO（输出 / 输入 / 方向）
//=============================================================================
module gpio (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        we,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_oe
);

    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_out <= 32'd0;
            gpio_oe  <= 32'd0;
        end else if (we) begin
            case (addr)
                2'd0: gpio_out <= wdata;
                2'd2: gpio_oe  <= wdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (addr)
            2'd1: rdata = gpio_in;
            2'd2: rdata = gpio_oe;
            default: rdata = gpio_out;
        endcase
    end

endmodule

// --------------------------------------------------------------------------
//  from: rtl/periph/timer.v
// --------------------------------------------------------------------------
//=============================================================================
//  timer.v : 64 位机器定时器 (mtime / mtimecmp)，产生 MTIP 电平中断
//=============================================================================
module timer (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        we,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        irq
);

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    always @(posedge clk) begin
        if (!rst_n) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            mtime <= mtime + 64'd1;
            if (we) begin
                case (addr)
                    2'd0: mtime[31:0]  <= wdata;
                    2'd1: mtime[63:32] <= wdata;
                    2'd2: mtimecmp[31:0]  <= wdata;
                    2'd3: mtimecmp[63:32] <= wdata;
                endcase
            end
        end
    end

    always @(*) begin
        case (addr)
            2'd0: rdata = mtime[31:0];
            2'd1: rdata = mtime[63:32];
            2'd2: rdata = mtimecmp[31:0];
            2'd3: rdata = mtimecmp[63:32];
            default: rdata = 32'd0;
        endcase
    end

    assign irq = (mtime >= mtimecmp);

endmodule

// --------------------------------------------------------------------------
//  from: rtl/soc/soc_top.v
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
//  from: rtl/soc/fpga_top.v
// --------------------------------------------------------------------------
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
