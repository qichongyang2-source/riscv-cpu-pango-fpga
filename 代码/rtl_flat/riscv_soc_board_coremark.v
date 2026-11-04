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
        mem[0] = 128'h79c28293100002970001011310010117;
        mem[1] = 128'h0002a0230062d863f783031310001317;
        mem[2] = 128'h300002b7291000efff5ff06f00428293;
        mem[3] = 128'h0000006f00a2a0230015151300050863;
        mem[4] = 128'h200007370000006f0062a02300100313;
        mem[5] = 128'h0017f79300072783200006b700470713;
        mem[6] = 128'h0000806700f6a0230ff57793fe079ce3;
        mem[7] = 128'h00470713200007370206866300054683;
        mem[8] = 128'h0017f793000727830015051320000637;
        mem[9] = 128'hfe0694e30005468300d62023fe079ce3;
        mem[10] = 128'h00072783200006b70047071320000737;
        mem[11] = 128'h00f6a02300a00793fe079ce30017f793;
        mem[12] = 128'hb80027f3b00025730000806700000513;
        mem[13] = 128'h002597830025150300060a6300008067;
        mem[14] = 128'h01079713000517830000806740f50533;
        mem[15] = 128'h00e7e7b3f007f7930087571301075713;
        mem[16] = 128'h01079713002515030005978300f51023;
        mem[17] = 128'h00e7e7b3f007f7930087571301075713;
        mem[18] = 128'h0000806740f505330025978300f59023;
        mem[19] = 128'h00112e230005140300812c23fe010113;
        mem[20] = 128'h01c1208300078c630017f79340745793;
        mem[21] = 128'h00008067020101130181240307f47513;
        mem[22] = 128'h00f706330047179300f7771340345713;
        mem[23] = 128'h00747693012128230131262300912a23;
        mem[24] = 128'h0006071300058493000509930385d783;
        mem[25] = 128'h0007861306c696630010061308068263;
        mem[26] = 128'h03c4d7830c1010ef0284851300070593;
        mem[27] = 128'h0384d783080798634109591301051913;
        mem[28] = 128'h0005079375d010ef0007859302a49e23;
        mem[29] = 128'h02f49c230085643307f97513f0047413;
        mem[30] = 128'h0181240301c120830089902308046413;
        mem[31] = 128'h0201011300c129830101290301412483;
        mem[32] = 128'h00040913010555130104151300008067;
        mem[33] = 128'h0220071300c6e46302100693fb5ff06f;
        mem[34] = 128'h0184a5030144a5830004960300249683;
        mem[35] = 128'h410959130105191303e4d7834a5010ef;
        mem[36] = 128'hf79ff06f0384d78302a49f2300079463;
        mem[37] = 128'h000605930005849300912223ff010113;
        mem[38] = 128'hec5ff0ef000604130081242300112623;
        mem[39] = 128'h00078413000485130004059300050793;
        mem[40] = 128'h0081240340a4053300c12083eb1ff0ef;
        mem[41] = 128'h00059703000080670101011300412483;
        mem[42] = 128'h0000806700f5112300e5102300259783;
        mem[43] = 128'h0006a70304e8f6630088089300062803;
        mem[44] = 128'h000527830116202304f3706300470313;
        mem[45] = 128'h0105202300f820230025960300059883;
        mem[46] = 128'h00478793000805130006a78300e82223;
        mem[47] = 128'h00c79123011790230048278300f6a023;
        mem[48] = 128'h00008067000805130000081300008067;
        mem[49] = 128'h004526030047a6830005250300050793;
        mem[50] = 128'h00e7a02300d5222300c7a22300052703;
        mem[51] = 128'h004526830045a6030000806700052023;
        mem[52] = 128'h00e5202300d5a22300c522230005a703;
        mem[53] = 128'h02074263002597030000806700a5a023;
        mem[54] = 128'h02050c63000525030000806700051863;
        mem[55] = 128'h00008067fee798e30027978300452783;
        mem[56] = 128'h0005250300c0006f0005970302050263;
        mem[57] = 128'hfee798e30007c7830045278300050c63;
        mem[58] = 128'h02050063000080670000051300008067;
        mem[59] = 128'h00052783000785130080006f00000713;
        mem[60] = 128'h00008067fe0798e30005071300e52023;
        mem[61] = 128'h0171262301512a2301312e23fd010113;
        mem[62] = 128'h0211262300100a9301a1202301812423;
        mem[63] = 128'h01412c23032120230291222302812423;
        mem[64] = 128'h00058c13000509930191222301612823;
        mem[65] = 128'h00000c930e098663000a8d1300060b93;
        mem[66] = 128'h00098793001c8c9300000b1300000913;
        mem[67] = 128'h001404130007a7830154586300000413;
        mem[68] = 128'h00098913000a8a1300090493fe079ae3;
        mem[69] = 128'h02099663060a00630280546300078993;
        mem[70] = 128'h0404806300092903fff4041300090793;
        mem[71] = 128'h11405263fe8040e30007849300f4a023;
        mem[72] = 128'h004925030049a58308040e6306098863;
        mem[73] = 128'h00098793fca054e3000c00e7000b8613;
        mem[74] = 128'h00078b13fc0494e30009a983fffa0a13;
        mem[75] = 128'hfff4041300092783fc5ff06f00078493;
        mem[76] = 128'h00090493020400630124a02302048063;
        mem[77] = 128'hfe0494e3fff404130009278300078913;
        mem[78] = 128'h00090493f40990e3fe0414e300090b13;
        mem[79] = 128'h001a9a93000b099305ac88630004a023;
        mem[80] = 128'h00098b130010007300002023f0099ee3;
        mem[81] = 128'h00078993fc078ce300098493020a0263;
        mem[82] = 128'h0134a023fe0482e3fffa0a130009a783;
        mem[83] = 128'hee0996e30007899300098913fe0a12e3;
        mem[84] = 128'h024124830281240302c12083fadff06f;
        mem[85] = 128'h01412a8301812a0301c1298302012903;
        mem[86] = 128'h00012d0300412c8300812c0300c12b83;
        mem[87] = 128'h000080670301011301012b03000b0513;
        mem[88] = 128'h00050613f65ff06fea0992e300048913;
        mem[89] = 128'h00112e2300812c23fe01011300451503;
        mem[90] = 128'h01412423013126230121282300912a23;
        mem[91] = 128'h2c05c4632aa05e630246240301512223;
        mem[92] = 128'h00000e9300000313000589932e040463;
        mem[93] = 128'h0004079300000a130000089300000e13;
        mem[94] = 128'h0047a703100786630007a78300c0006f;
        mem[95] = 128'h0080006f00000693ff3818e300271803;
        mem[96] = 128'h0004069300d420230004270300070413;
        mem[97] = 128'h000717030047a7030e078463fe0718e3;
        mem[98] = 128'h001777134097571300068c6300177693;
        mem[99] = 128'h0007a7030108d8930107189300e88733;
        mem[100] = 128'h0004278300d7a0230007268300070c63;
        mem[101] = 128'h010e1e13001e0e1300e4202300f72023;
        mem[102] = 128'h010793130013079306084663010e5e13;
        mem[103] = 128'h41035313010797930109999300180993;
        mem[104] = 128'h0ff7fa130a6502630107d7934109d993;
        mem[105] = 128'hf409d0e3ffff883700040793000a0693;
        mem[106] = 128'h0007a783f4da08e300074a030047a703;
        mem[107] = 128'hf2da0ee300074a030047a70300078c63;
        mem[108] = 128'hf2dff06f00068a13fe0798e30007a783;
        mem[109] = 128'h01069693410353130106931300130693;
        mem[110] = 128'h000407930ff6f693046502630106d693;
        mem[111] = 128'h00042783f01ff06f00098813fc5ff06f;
        mem[112] = 128'h010ede930047a783010e9e93001e8e93;
        mem[113] = 128'h0107989300f887b30017f79300178783;
        mem[114] = 128'h002e179300080993f41ff06f0108d893;
        mem[115] = 128'h0104d4930108949300f888b341d787b3;
        mem[116] = 128'hc85ff0ef250005930004051300b05a63;
        mem[117] = 128'h0007aa83000409130004278300050413;
        mem[118] = 128'h00c7a223000aa683004aa6030047a703;
        mem[119] = 128'h0009d863000aa02300d7a02300eaa223;
        mem[120] = 128'h004927830c090263000929030bc0006f;
        mem[121] = 128'h0004859300442783ff3798e300279783;
        mem[122] = 128'h0005049300092903325010ef00079503;
        mem[123] = 128'h00492683004aa70300042903fe0914e3;
        mem[124] = 128'h00faa02300e9222300daa22300092783;
        mem[125] = 128'h000006130d4005930159202300040513;
        mem[126] = 128'h020400630005091300052403bf1ff0ef;
        mem[127] = 128'h2cd010ef000795030004859300492783;
        mem[128] = 128'h01c12083fe0414e30005049300042403;
        mem[129] = 128'h00812a0300c129830101290301812403;
        mem[130] = 128'h02010113014124830004851300412a83;
        mem[131] = 128'h0049278300090a630009290300008067;
        mem[132] = 128'h00042903f51ff06ffefa18e30007c783;
        mem[133] = 128'h000795030004859300442783f60906e3;
        mem[134] = 128'hf20916e30005049300092903269010ef;
        mem[135] = 128'h00000a130000049300058993f45ff06f;
        mem[136] = 128'h000407930005881302040263ec1ff06f;
        mem[137] = 128'h00000e93000006930000031300000893;
        mem[138] = 128'h0010007300002783e11ff06f00000e13;
        mem[139] = 128'hffff87b702f53333ccd78793ccccd7b7;
        mem[140] = 128'h0005851301058693080787930005a023;
        mem[141] = 128'h00331e93ffe303130043531300858e13;
        mem[142] = 128'h00231f9300fe902301d5a22301d58eb3;
        mem[143] = 128'hffff87b7004e871301fe8fb3000e9123;
        mem[144] = 128'h00e5a62311f8fc63008e889313d6f063;
        mem[145] = 128'hfff00713fff7c79301c5a0230005a423;
        mem[146] = 128'h0106129306030a6300ee922300fe9323;
        mem[147] = 128'h00000813fff3c3930102d293ffff83b7;
        mem[148] = 128'h00379793005747b30107571301081713;
        mem[149] = 128'h00879f1300e7e7b30787f79300777713;
        mem[150] = 128'h01e787b3004887130018081300868593;
        mem[151] = 128'h00d5202301c6a02303f7726303d5f463;
        mem[152] = 128'h00068e130078912300f890230116a223;
        mem[153] = 128'h000e2803fb0314e30005869300070893;
        mem[154] = 128'h02f33333ccd78793ccccd7b706080a63;
        mem[155] = 128'h0010069320000713fffe8e9300004eb7;
        mem[156] = 128'h00d645b3000888130080006f00235313;
        mem[157] = 128'h0107979301d7f7b300b7e7b370077793;
        mem[158] = 128'h010697930066f6634107d793004e2583;
        mem[159] = 128'h0107171310070713000828834107d793;
        mem[160] = 128'h00080e13001686930107571300f59123;
        mem[161] = 128'h9b5ff06f000006130d400593fa089ce3;
        mem[162] = 128'hefdff06f00000e1300070893000e0693;
        mem[163] = 128'h0011262301c5290301212023ff010113;
        mem[164] = 128'h0081242304090e6302052e2302052c23;
        mem[165] = 128'h00100593000004930005041300912223;
        mem[166] = 128'h6b8010ef03845583b29ff0ef00040513;
        mem[167] = 128'hb11ff0ef00040513fff0059302a41c23;
        mem[168] = 128'h0004946302a41c236a0010ef03845583;
        mem[169] = 128'h00812403fc9912e30014849302a41d23;
        mem[170] = 128'h000005130001290300c1208300412483;
        mem[171] = 128'h00810613f80101130000806701010113;
        mem[172] = 128'h06812c2306112e2304e1051300410593;
        mem[173] = 128'h05812c23073126230721282306912a23;
        mem[174] = 128'h58c010ef001005130d5010ef00012223;
        mem[175] = 128'h57c010ef00f116230020051300050793;
        mem[176] = 128'h56c010ef00f117230030051300050793;
        mem[177] = 128'h55c010ef00f118230040051300050793;
        mem[178] = 128'h54c010ef02f124230050051300050793;
        mem[179] = 128'h02a1262300c127830070051300051463;
        mem[180] = 128'h1000083734078e63010117831e079063;
        mem[181] = 128'h0015771300f037b3002577937a480813;
        mem[182] = 128'h00f707330045769301012a2304011623;
        mem[183] = 128'h01075713010717130017071300068863;
        mem[184] = 128'h0000079300c1069302e5d5b37d000593;
        mem[185] = 128'h02b12223003008930010031300000613;
        mem[186] = 128'h14071c630017879300a7773300f31733;
        mem[187] = 128'h0017f71302c12783ff1796e300468693;
        mem[188] = 128'h024125030181258300c1160300070e63;
        mem[189] = 128'h0027f71302a1282302c12783ce1ff0ef;
        mem[190] = 128'h0201260300078a630047f7930e071e63;
        mem[191] = 128'h028127836ad000ef0241250300c11583;
        mem[192] = 128'h0281270302f124230010079304079a63;
        mem[193] = 128'h02f124230017979300e787b300271793;
        mem[194] = 128'h750010efe09ff0ef00c1051374c010ef;
        mem[195] = 128'h00a00793fc050ae3770010ef75c010ef;
        mem[196] = 128'h02f707b3001787930281270302a7d7b3;
        mem[197] = 128'hdd5ff0ef00c10513718010ef02f12423;
        mem[198] = 128'h00c1150300050913728010ef71c010ef;
        mem[199] = 128'h00e1150300050593654010ef00000593;
        mem[200] = 128'h63c010ef0101150300050593648010ef;
        mem[201] = 128'h000087b7630010ef0241150300050593;
        mem[202] = 128'h08a7fe6350f5066300050993b0578793;
        mem[203] = 128'h0000f7b74ef50463a0278793000097b7;
        mem[204] = 128'h09050513100005371ef516639f578793;
        mem[205] = 128'h00e117830980006f00300793201010ef;
        mem[206] = 128'h010797930241250301c1258300c11603;
        mem[207] = 128'h02c127834f8000ef0341069300c7e633;
        mem[208] = 128'h010616130016061302b60733ee5ff06f;
        mem[209] = 128'he95ff06f00e6a62300e8073301065613;
        mem[210] = 128'he20790e301011783e2e794e300100713;
        mem[211] = 128'h00f126230660071341578793341537b7;
        mem[212] = 128'h8f278793000027b7e09ff06f00e11823;
        mem[213] = 128'h14f51a63eaf78793000057b746f50c63;
        mem[214] = 128'h00200793169010ef05c5051310000537;
        mem[215] = 128'h05912a2346070263798c270310000c37;
        mem[216] = 128'h07412423518c8c930017979310000cb7;
        mem[217] = 128'h05a1282305712e230761202307512223;
        mem[218] = 128'h10000b3700000b9300000d1300fc8cb3;
        mem[219] = 128'h002404330340006f10000a3710000ab7;
        mem[220] = 128'h01a787b3798c2703001b8b9304c45783;
        mem[221] = 128'h010bdb9301079d1301079493010b9b93;
        mem[222] = 128'h004b941332ebfe63410d5d130104d493;
        mem[223] = 128'h002784b30504879300249493017404b3;
        mem[224] = 128'h020706630017f713fe049e23fdc4a783;
        mem[225] = 128'h000b859302d60063000cd683ff64d603;
        mem[226] = 128'hfdc4a783ffc4d7030ad010ef0ecb0513;
        mem[227] = 128'h02070e630027f713fee49e2300170713;
        mem[228] = 128'h002704b30504871300249493017404b3;
        mem[229] = 128'h000b859302d6006300ccd683ff84d603;
        mem[230] = 128'hfdc4a783ffc4d70306d010ef11ca8513;
        mem[231] = 128'h0047f79301740433fee49e2300170713;
        mem[232] = 128'h0027843305040793f2078ce300241413;
        mem[233] = 128'hffc4578326d61463018cd683ffa45603;
        mem[234] = 128'hca1ff06f00f1182306600793f25ff06f;
        mem[235] = 128'h4a0010ef10000c37fff4049300010437;
        mem[236] = 128'h18078513009504b3100007b702412583;
        mem[237] = 128'h198505130009059310000537001010ef;
        mem[238] = 128'h000505934bc010ef000905137f0010ef;
        mem[239] = 128'h010494937d8010ef1b05051310000537;
        mem[240] = 128'h2605146349c010ef0104d49300090513;
        mem[241] = 128'h24a7f26300900793490010ef00090513;
        mem[242] = 128'h220505131000053702812583798c2783;
        mem[243] = 128'h794010ef4104d4930104949302f585b3;
        mem[244] = 128'h244505132385859310000537100005b7;
        mem[245] = 128'h25c5859310000537100005b7780010ef;
        mem[246] = 128'h10000537100005b776c010ef27050513;
        mem[247] = 128'h10000537758010ef2905051328858593;
        mem[248] = 128'h02c12783748010ef2a85051300098593;
        mem[249] = 128'h04070263798c2703040706630017f713;
        mem[250] = 128'h008787b3004417931000093700000413;
        mem[251] = 128'h000405930467d603002787b300279793;
        mem[252] = 128'h798c27830014041370c010ef2c490513;
        mem[253] = 128'h02c12783fcf468e30104541301041413;
        mem[254] = 128'h1e070c63798c2703040706630027f713;
        mem[255] = 128'h008787b3004417931000093700000413;
        mem[256] = 128'h000405930487d603002787b300279793;
        mem[257] = 128'h798c2783001404136bc010ef2e090513;
        mem[258] = 128'h02c12783fcf468e30104541301041413;
        mem[259] = 128'h08078263798c2783040784630047f793;
        mem[260] = 128'h008787b3004417931000093700000413;
        mem[261] = 128'h0004059304a7d603002787b300279793;
        mem[262] = 128'h798c27830014041366c010ef2fc90513;
        mem[263] = 128'h798c2783fcf468e30104541301041413;
        mem[264] = 128'h0044179302078c631000093700000413;
        mem[265] = 128'h0447d603002787b300279793008787b3;
        mem[266] = 128'h00140413628010ef3189051300040593;
        mem[267] = 128'hfcf468e30104541301041413798c2783;
        mem[268] = 128'h380505131000053706904e6308048863;
        mem[269] = 128'h07c120832ec010ef04e10513600010ef;
        mem[270] = 128'h06c12983070129030741248307812403;
        mem[271] = 128'h00008067080101130000051305812c03;
        mem[272] = 128'hffc457835c8010ef150a0513000b8593;
        mem[273] = 128'hfef41e230107d7930107979300178793;
        mem[274] = 128'h06012b0306412a8306812a03ca5ff06f;
        mem[275] = 128'hd81ff06f05012d0305412c8305c12b83;
        mem[276] = 128'hf89ff06f588010ef3e45051310000537;
        mem[277] = 128'hf79ff06f578010ef3345051310000537;
        mem[278] = 128'h00148493568010ef1e05051310000537;
        mem[279] = 128'h00090513798c278302812403db1ff06f;
        mem[280] = 128'h1000053700050593220010ef02f40433;
        mem[281] = 128'hd75ff06f538010ef02b455b31c850513;
        mem[282] = 128'h00000793528010ef0005051310000537;
        mem[283] = 128'h514010ef0305051310000537bc1ff06f;
        mem[284] = 128'h0c05051310000537badff06f00100793;
        mem[285] = 128'h00000493b99ff06f00400793500010ef;
        mem[286] = 128'hed5ff06fe8078ae30047f793cddff06f;
        mem[287] = 128'h000508130091242300812623ff010113;
        mem[288] = 128'hffc5f293fff585930010061300061463;
        mem[289] = 128'h000785130e0804630000079300428413;
        mem[290] = 128'hff0768e30037171302f7873300178793;
        mem[291] = 128'h0c050e63007402b30013939302a503b3;
        mem[292] = 128'h00151913001503130005049301212223;
        mem[293] = 128'h40540e330010071300000e9300028f13;
        mem[294] = 128'h0107179302e60633000f081300070f93;
        mem[295] = 128'h0028081300170713010e08b30107d793;
        mem[296] = 128'h0106161300b606330105d59341f65593;
        mem[297] = 128'h0105959300c785b340b6063301065613;
        mem[298] = 128'h0ff7f793feb81f2300f587b30105d593;
        mem[299] = 128'h01f50733001e8e93fa671ae300f89023;
        mem[300] = 128'h00412903f8ae9ce3012f0f3300a30333;
        mem[301] = 128'hffc7f7930086a223fff78793007287b3;
        mem[302] = 128'h00f6a6230096a0230047879300c12403;
        mem[303] = 128'h0000806701010113008124830056a423;
        mem[304] = 128'h000485130062829301212223fff00493;
        mem[305] = 128'h0000049300000393f35ff06f00200393;
        mem[306] = 128'h00251f930805046300050e93fb1ff06f;
        mem[307] = 128'h00000313003f1f1301f588b340a00f33;
        mem[308] = 128'h41f88e33000008130000069300000513;
        mem[309] = 128'h00470713010795130140006f000e0713;
        mem[310] = 128'h010517930006859302e88e6341055513;
        mem[311] = 128'h00d5a5b300a785130107d79300072683;
        mem[312] = 128'h00b787b34105551300d8083301051513;
        mem[313] = 128'hfce896e30000081300470713fd0654e3;
        mem[314] = 128'h00008067fa6e92e341ee08b300130313;
        mem[315] = 128'h00151f1304050a630000806700000513;
        mem[316] = 128'h00000313002e9e9301e6083340a00eb3;
        mem[317] = 128'h000e07930023161341e80e3300000893;
        mem[318] = 128'h00460613002787930007970300c58633;
        mem[319] = 128'h00188893ff0796e3fee62e2302d70733;
        mem[320] = 128'h00008067fd1516e341de083300a30333;
        mem[321] = 128'h0106161340a008b30015131304050463;
        mem[322] = 128'h000005930028989301065613006586b3;
        mem[323] = 128'h002787930007d7030008079340668833;
        mem[324] = 128'h00158593fef698e3fee79f2300e60733;
        mem[325] = 128'h04050a6300008067fcb51ee3411806b3;
        mem[326] = 128'h01c68e3301e58f3300151e1300251f13;
        mem[327] = 128'h0006879301060833001e981300000e93;
        mem[328] = 128'h00278793000793030008170300000893;
        mem[329] = 128'hfefe14e300e888b30267073300280813;
        mem[330] = 128'hfcbf14e300ae8eb3004585930115a023;
        mem[331] = 128'h00050f13ff0101130a05046300008067;
        mem[332] = 128'h00068413000583930081262300151513;
        mem[333] = 128'h0000029300000f9300a6083300060e93;
        mem[334] = 128'h00000e1300040313011388b3002f9893;
        mem[335] = 128'h0007970300000613000e879300030693;
        mem[336] = 128'h02b7073300a686b30027879300069583;
        mem[337] = 128'h001e079300c8a023fef814e300e60633;
        mem[338] = 128'h00078e1300ff06630023031300488893;
        mem[339] = 128'h00a8083301ef8fb300ae8eb3fc1ff06f;
        mem[340] = 128'hf95ff06f0007829301c2866300128793;
        mem[341] = 128'h00008067000080670101011300c12403;
        mem[342] = 128'h0015151300050f13ff0101130a050e63;
        mem[343] = 128'h00060e93000684130005839300812623;
        mem[344] = 128'h002f98930000029300000f9300a60833;
        mem[345] = 128'h0003061300000e1300040313011388b3;
        mem[346] = 128'h000697830006170300000593000e8693;
        mem[347] = 128'h4027d71302e787b300a6063300268693;
        mem[348] = 128'h02f707b307f7f79300f777134057d793;
        mem[349] = 128'h001e079300b8a023fcd81ae300f585b3;
        mem[350] = 128'h00078e1300ff06630023031300488893;
        mem[351] = 128'h00a8083301ef8fb300ae8eb3fadff06f;
        mem[352] = 128'hf81ff06f0007829301c2866300128793;
        mem[353] = 128'h00008067000080670101011300c12403;
        mem[354] = 128'h01412c230291222302812423fd010113;
        mem[355] = 128'h0321202302112623fffffa3701512a23;
        mem[356] = 128'h01476a33000684930006041300058a93;
        mem[357] = 128'h0181242301312e230015131338050e63;
        mem[358] = 128'h017126230107199340a00c33006605b3;
        mem[359] = 128'h0005089301a120230191222301612823;
        mem[360] = 128'h00000b930109d993002c1c1300058613;
        mem[361] = 128'h002787930007d6830008079340660833;
        mem[362] = 128'h001b8913fec798e3fed79f2300d986b3;
        mem[363] = 128'hfd5ff06f00090b930128866341880633;
        mem[364] = 128'h00251613406588330000089300000513;
        mem[365] = 128'h00278793000796830156063300080793;
        mem[366] = 128'hfef596e3fed62e2302e686b300460613;
        mem[367] = 128'h0178866300188793418805b301250533;
        mem[368] = 128'h41200d33418a8cb3fc5ff06f00078893;
        mem[369] = 128'h0000059300000693003d1d13000c8813;
        mem[370] = 128'h00088713018808b30000031300000513;
        mem[371] = 128'h4105551300470713010795130140006f;
        mem[372] = 128'h00072683010517930006861302e80e63;
        mem[373] = 128'h0105151300d6263300a785130107d793;
        mem[374] = 128'hfcba54e300c787b34105551300d585b3;
        mem[375] = 128'h41a88833fce816e30000059300470713;
        mem[376] = 128'hf9dff06f00078313006b866300130793;
        mem[377] = 128'h000a859300048693335000ef00000593;
        mem[378] = 128'hcb1ff0ef000905130004061300050b13;
        mem[379] = 128'h00000893000005130000059300000693;
        mem[380] = 128'h010795130140006f00080713019c0833;
        mem[381] = 128'h0006861303970e634105551300470713;
        mem[382] = 128'h00a785130107d7930007268301051793;
        mem[383] = 128'h4105551300d585b30105151300d62633;
        mem[384] = 128'h0000059300470713fcba54e300c787b3;
        mem[385] = 128'h017886630018879341a80cb3fd9716e3;
        mem[386] = 128'h29d000ef000b0593f9dff06f00078893;
        mem[387] = 128'h000905130004869300050b1300040613;
        mem[388] = 128'h0000071300000313c71ff0ef000a8593;
        mem[389] = 128'h00231593000008930000051300000613;
        mem[390] = 128'h010795130180006f0000081300ba85b3;
        mem[391] = 128'h05287063004585934105551300180813;
        mem[392] = 128'h0107d7930005a7030105179300070693;
        mem[393] = 128'h00e606330105151300e6a6b300a78513;
        mem[394] = 128'h00180813fcca52e300d787b341055513;
        mem[395] = 128'h00188893fd2864e30045859300000613;
        mem[396] = 128'h1fd000ef000b0593f928ece301230333;
        mem[397] = 128'h00090513000406130004869300050793;
        mem[398] = 128'h00000313c79ff0ef00078493000a8593;
        mem[399] = 128'h00000893000005130000061300000713;
        mem[400] = 128'h0180006f0000081300ba85b300231593;
        mem[401] = 128'h00458593410555130018081301079513;
        mem[402] = 128'h0005a703010517930007069305287063;
        mem[403] = 128'h0105151300e6a6b300a785130107d793;
        mem[404] = 128'hfcca52e300d787b34105551300e60633;
        mem[405] = 128'hfd2864e3004585930000061300180813;
        mem[406] = 128'h00048593f928ece30123033300188893;
        mem[407] = 128'h001597930000061300000593159000ef;
        mem[408] = 128'h001686930007d7030000069300f407b3;
        mem[409] = 128'hff26e6e3fee79f234137073300278793;
        mem[410] = 128'h01c12983fd266ae3012585b300160613;
        mem[411] = 128'h00412c8300812c0300c12b8301012b03;
        mem[412] = 128'h010515130281240302c1208300012d03;
        mem[413] = 128'h01412a8301812a030201290302412483;
        mem[414] = 128'h00000593000080670301011341055513;
        mem[415] = 128'h0005091300040613000486930d9000ef;
        mem[416] = 128'h00090593a55ff0ef00000513000a8593;
        mem[417] = 128'h00040613000486930b5000ef00000513;
        mem[418] = 128'ha89ff0ef00000513000a859300050913;
        mem[419] = 128'h00050793091000ef0000051300090593;
        mem[420] = 128'h0000051300048693000a859300040613;
        mem[421] = 128'h0000051300040593b0dff0ef00078413;
        mem[422] = 128'h00812423ff010113f61ff06f069000ef;
        mem[423] = 128'h00452603000587130006041300852683;
        mem[424] = 128'hb95ff0ef001126230005250300c52583;
        mem[425] = 128'h0101011300c120830081240300040593;
        mem[426] = 128'h111e7e6300100e13fff508930290006f;
        mem[427] = 128'hff0101130105d5930105959301c585b3;
        mem[428] = 128'h00700313008126230035d79310000837;
        mem[429] = 128'h00400e930000071353c808130075f693;
        mem[430] = 128'h0cdee46306668e630037f79302c00f13;
        mem[431] = 128'h0106d6930027979301069693ffd68693;
        mem[432] = 128'h008002930107a7830ade626300f807b3;
        mem[433] = 128'h00e60733071474630056843300170693;
        mem[434] = 128'h001787930007cf83005783b300070693;
        mem[435] = 128'h00158593fef398e3fff68fa300168693;
        mem[436] = 128'h01e70023005707330105d59301059593;
        mem[437] = 128'h0037f793000407130075f6930035d793;
        mem[438] = 128'h001706930080029300279793f86696e3;
        mem[439] = 128'hfb1460e30307a7830056843300f807b3;
        mem[440] = 128'h00e60733001686930180006f00a76663;
        mem[441] = 128'h00c12403fea6e8e30006871300070023;
        mem[442] = 128'h004002930007a7830000806701010113;
        mem[443] = 128'h0207a78300f807b300279793f61ff06f;
        mem[444] = 128'h00000713000e0693f4dff06f00800293;
        mem[445] = 128'h0007002300e60733001686930080006f;
        mem[446] = 128'h0005268300008067fea6e8e300068713;
        mem[447] = 128'h02c0071326078e630006c78300050613;
        mem[448] = 128'h2307866302e008131ee78c6300000513;
        mem[449] = 128'h020786630fd7f793fd5787931ef86a63;
        mem[450] = 128'h00170713001686930005a7830045a703;
        mem[451] = 128'h0010051300f5a02300e5a22300178793;
        mem[452] = 128'h001687930005a5030000806700d62023;
        mem[453] = 128'h260886630016c88300a5a02300150513;
        mem[454] = 128'h0ff77713fd0887130085a50320e88263;
        mem[455] = 128'h1f08806300e37e630015051300900313;
        mem[456] = 128'h00d62023001005130026869300a5a423;
        mem[457] = 128'h001787930017c68300a5a42300008067;
        mem[458] = 128'h02e007131ee68e6302c0071318068663;
        mem[459] = 128'h009007130ff6f693fd06869302e68863;
        mem[460] = 128'h00178693001005130105a703fcd77ce3;
        mem[461] = 128'h0000806700d6202300f5a82300a707b3;
        mem[462] = 128'h0017c68300e5a823001707130105a703;
        mem[463] = 128'h0ee68c6302c0071314068e6300178793;
        mem[464] = 128'hfd06869302a70863045005130df6f713;
        mem[465] = 128'h0145a703fcd77ae3009007130ff6f693;
        mem[466] = 128'h00f5aa2300a707b30017869300100513;
        mem[467] = 128'h001786930145a7030000806700d62023;
        mem[468] = 128'h12070c630017c70300e5aa2300170713;
        mem[469] = 128'hfd57071300c5a68314a7026302c00513;
        mem[470] = 128'h00070a6300d5a623001686930fd77713;
        mem[471] = 128'h0000806700d620230010051300278693;
        mem[472] = 128'h10a700630e070a63002786930027c703;
        mem[473] = 128'h001808130ff77713fd0707130185a803;
        mem[474] = 128'h0037869300e578630105ac2300900513;
        mem[475] = 128'h0016c70300068813e8dff06f00100513;
        mem[476] = 128'h0ff7f793fd07079302c0089300168693;
        mem[477] = 128'h0045a783fef570e30f1700630e070863;
        mem[478] = 128'h00f5a22300a787b30028069300100513;
        mem[479] = 128'h001686930050051300078693e51ff06f;
        mem[480] = 128'h009005130ff7f793fd078793e41ff06f;
        mem[481] = 128'h00150513001687930005a503e0f568e3;
        mem[482] = 128'h00078693e80690e30016c68300a5a023;
        mem[483] = 128'h001687930005a503e0dff06f00400513;
        mem[484] = 128'hea0698e30016c68300a5a02300150513;
        mem[485] = 128'h00a5a423de9ff06f0050051300078693;
        mem[486] = 128'h001686930020051300078693e8dff06f;
        mem[487] = 128'h00600513dc9ff06f00000513dd1ff06f;
        mem[488] = 128'h00600513db9ff06f00300513dc1ff06f;
        mem[489] = 128'h0016869300300513dadff06f00168693;
        mem[490] = 128'h001686930040051300078693da1ff06f;
        mem[491] = 128'hd85ff06f0016869300700513d91ff06f;
        mem[492] = 128'h0020051300078693d7dff06f00700513;
        mem[493] = 128'h0741242307312623f8010113d71ff06f;
        mem[494] = 128'h06912a2306812c2303010a1301010993;
        mem[495] = 128'h05812c2305712e230751222307212823;
        mem[496] = 128'h06112e230007849300070a9305912a23;
        mem[497] = 128'h00050c1300b126230005841307612023;
        mem[498] = 128'h00098913000a079300068b9300060c93;
        mem[499] = 128'h00478793000720230007a02300098713;
        mem[500] = 128'h00044783fed796e30047071305010693;
        mem[501] = 128'h000b05130301059310078c6300c10b13;
        mem[502] = 128'h00c127030109883300251813c8dff0ef;
        mem[503] = 128'h00f82023001787930007470300082783;
        mem[504] = 128'h0384786301840c3300812623fc071ce3;
        mem[505] = 128'h019746b30007c70302c0061300040793;
        mem[506] = 128'hff87e6e3015787b300d7802300c70463;
        mem[507] = 128'h030105930207886300c10b1300044783;
        mem[508] = 128'h00c9863300251613c29ff0ef000b0513;
        mem[509] = 128'h00178793000747030006278300c12703;
        mem[510] = 128'h02c0069300812623fc071ce300f62023;
        mem[511] = 128'h00d784630177c7330004478301847e63;
        mem[512] = 128'h02098993ff8466e30154043300e40023;
        mem[513] = 128'h194000ef004909130004859300092503;
        mem[514] = 128'h184000ef004a0a13000a250300050593;
        mem[515] = 128'h0781240307c12083fd299ee300050493;
        mem[516] = 128'h06812a0306c129830701290307412483;
        mem[517] = 128'h05812c0305c12b8306012b0306412a83;
        mem[518] = 128'h01840c33000080670801011305412c83;
        mem[519] = 128'h04a7ec6300500793f99ff06ff38460e3;
        mem[520] = 128'h00f505330025151357c78793100007b7;
        mem[521] = 128'hf7c7a503100017b70007806700052783;
        mem[522] = 128'h00008067f847a503100017b700008067;
        mem[523] = 128'h100007b700008067f807a503100017b7;
        mem[524] = 128'h79c7a503100007b7000080677a07a503;
        mem[525] = 128'hffffa637000080670000051300008067;
        mem[526] = 128'h00800713000585130016061300050693;
        mem[527] = 128'h0015551340f007b30017f79300a6c7b3;
        mem[528] = 128'h0107951300a7c7b3fff7071300c7f7b3;
        mem[529] = 128'hfc071ae30016d693010555130ff77713;
        mem[530] = 128'h00058513ffffa7b70005069300008067;
        mem[531] = 128'h00a647b300800713001785930ff6f613;
        mem[532] = 128'h0015551300b7f7b340f007b30017f793;
        mem[533] = 128'h0ff777130105151300f54533fff70713;
        mem[534] = 128'hffffa637fc071ae30016561301055513;
        mem[535] = 128'h00a6c7b300800713001606130086d693;
        mem[536] = 128'h00c7f7b30015551340f007b30017f793;
        mem[537] = 128'h0ff777130107951300a7c7b3fff70713;
        mem[538] = 128'h00008067fc071ae30016d69301055513;
        mem[539] = 128'h00058513ffffa8370105161300050693;
        mem[540] = 128'h00800713001808130ff6f59301065613;
        mem[541] = 128'h0015551340f007b30017f79300a5c7b3;
        mem[542] = 128'h0107951300a7c7b3fff707130107f7b3;
        mem[543] = 128'hfc071ae30015d593010555130ff77713;
        mem[544] = 128'h008007130015859300865613ffffa5b7;
        mem[545] = 128'h0015551340f007b30017f79300a647b3;
        mem[546] = 128'h0107951300a7c7b3fff7071300b7f7b3;
        mem[547] = 128'hfc071ae300165613010555130ff77713;
        mem[548] = 128'h001585930ff6f613ffffa5b70106d693;
        mem[549] = 128'h40f007b30017f79300a647b300800713;
        mem[550] = 128'h00f54533fff707130015551300b7f7b3;
        mem[551] = 128'h00165613010555130ff7771301051513;
        mem[552] = 128'h001606130086d693ffffa637fc071ae3;
        mem[553] = 128'h40f007b30017f79300a6c7b300800713;
        mem[554] = 128'h00f54533fff707130015551300c7f7b3;
        mem[555] = 128'h0016d693010555130ff7771301051513;
        mem[556] = 128'h010516130005069300008067fc071ae3;
        mem[557] = 128'h0ff6f6930106561300058513ffffa7b7;
        mem[558] = 128'h0017f79300a6c7b30080071300178593;
        mem[559] = 128'hfff707130015551300b7f7b340f007b3;
        mem[560] = 128'h010555130ff777130105151300f54533;
        mem[561] = 128'h00865693ffffa7b7fc071ae30016d693;
        mem[562] = 128'h0017f79300a6c7b30017861300800713;
        mem[563] = 128'hfff7071300c7f7b30015551340f007b3;
        mem[564] = 128'h010555130ff777130107951300a7c7b3;
        mem[565] = 128'h0000051300008067fc071ae30016d693;
        mem[566] = 128'hb000277300008067b000257300008067;
        mem[567] = 128'hb000277300008067f6e7ac23100017b7;
        mem[568] = 128'h1000173700008067f6e7aa23100017b7;
        mem[569] = 128'h40f50533f787a783f7472503100017b7;
        mem[570] = 128'h02f53533b897879355e647b700008067;
        mem[571] = 128'h00f50023001007930000806701855513;
        mem[572] = 128'hfa010113000080670005002300008067;
        mem[573] = 128'h0e0810630407f81304912c2304812e23;
        mem[574] = 128'h0e0390634c0f8f930107f39310000fb7;
        mem[575] = 128'h0027f813ff0f7f13fff40f130017f413;
        mem[576] = 128'h2205ca630c080e630207f293030f0f13;
        mem[577] = 128'h000004930087f793200812630047f813;
        mem[578] = 128'h0202806302000493fff6869300078663;
        mem[579] = 128'h40f607b30080079324f60a6301000793;
        mem[580] = 128'h180592630200029340f686b30017b793;
        mem[581] = 128'h0010081300000e9300f1062303000793;
        mem[582] = 128'h0007031300e854630008031300c10e13;
        mem[583] = 128'h0005079300d505b306041e63406686b3;
        mem[584] = 128'hff178fa30017879306d0546302000893;
        mem[585] = 128'h00028a631604966300078513feb79ce3;
        mem[586] = 128'h16f60c63010007931cf6046300800793;
        mem[587] = 128'h10000fb707c0006fffe68693007036b3;
        mem[588] = 128'hffe7f793f20384e34e8f8f930107f393;
        mem[589] = 128'h0207f29302000f13010004130027f813;
        mem[590] = 128'hfff68693f45ff06f00000493f20816e3;
        mem[591] = 128'h00028a63001505130095002300048663;
        mem[592] = 128'h10f60e630100079318f6086300800793;
        mem[593] = 128'h1ad054630005079300d505b302039263;
        mem[594] = 128'h00078513feb79ce3ffe78fa300178793;
        mem[595] = 128'h03000593006508b300050793fff00693;
        mem[596] = 128'hfeb78fa340f886330017879302e85663;
        mem[597] = 128'h410307b300e8566300000793fec84ae3;
        mem[598] = 128'h01de07b300f5053300178793fff78793;
        mem[599] = 128'h00170713000786130007c58300050713;
        mem[600] = 128'h01d507b3fece16e3fff78793feb70fa3;
        mem[601] = 128'h0016871302d050630005851300178593;
        mem[602] = 128'h0015051300c500230200061300f70733;
        mem[603] = 128'h0581248305c1240300b68533fea71ce3;
        mem[604] = 128'h02d00493000786930000806706010113;
        mem[605] = 128'h00080e9302c5f7b300c10e1300000813;
        mem[606] = 128'h00ff87b300058893010e033300180813;
        mem[607] = 128'hfcc8fee3fef30fa302c5d5b30007c783;
        mem[608] = 128'h060286630017851300978023e65ff06f;
        mem[609] = 128'h02b00493fff68693eedff06ffff00693;
        mem[610] = 128'h0780079303000613fff00693e0dff06f;
        mem[611] = 128'hed5ff06f0025051300f500a300c50023;
        mem[612] = 128'h01000813f80280e3fff6879340b005b3;
        mem[613] = 128'h00078693050606630080081307060263;
        mem[614] = 128'h03000793f69ff06f0200029302d00493;
        mem[615] = 128'hea038ce3ffe006930015051300f50023;
        mem[616] = 128'h02000293ffe68693eb1ff06ffff00693;
        mem[617] = 128'h0015051300f5002303000793dbdff06f;
        mem[618] = 128'h0200029302d00493ffe68693e71ff06f;
        mem[619] = 128'h0200029302d00493ffd68693f21ff06f;
        mem[620] = 128'h981fd06fe6dff06ffff68693f11ff06f;
        mem[621] = 128'h448124234411262345212023b9010113;
        mem[622] = 128'h44d12e2344c12c2344b12a2344912223;
        mem[623] = 128'h471126234701242346f1222346e12023;
        mem[624] = 128'h78078c63012122234541091300054783;
        mem[625] = 128'h43512a2343412c2343312e2302010413;
        mem[626] = 128'h43812423000503134371262343612823;
        mem[627] = 128'h100009b70100049302500a1300040513;
        mem[628] = 128'h07478a6304c00a9302e00b1300900b93;
        mem[629] = 128'h00130313001505130013478300f50023;
        mem[630] = 128'h43412a8343812a0343c12983fe0796e3;
        mem[631] = 128'h0005002342812c0342c12b8343012b03;
        mem[632] = 128'h8c1fd0ef0004049372050a6302014503;
        mem[633] = 128'hfe0518e3001484930014c50300048793;
        mem[634] = 128'h44412483448124034087853344c12083;
        mem[635] = 128'h00008067470101130015051344012903;
        mem[636] = 128'hfe060713001305930013460300000793;
        mem[637] = 128'h594986930027171300e4ec630ff77713;
        mem[638] = 128'hfd060713000700670007270300d70733;
        mem[639] = 128'hfff0069302a0071310ebf2630ff77713;
        mem[640] = 128'h0df678130d660263fff0071312e60663;
        mem[641] = 128'h037008930ff87813fbf6081309580463;
        mem[642] = 128'h5d88889300281813100008b70508ec63;
        mem[643] = 128'h0017e793000800670008280301180833;
        mem[644] = 128'h000583130107e793f81ff06f00058313;
        mem[645] = 128'hf69ff06f000583130047e793f75ff06f;
        mem[646] = 128'h0087e793f5dff06f000583130207e793;
        mem[647] = 128'h0250079300058c13f51ff06f00058313;
        mem[648] = 128'h00150513000c478300f5002328f60663;
        mem[649] = 128'h0015c6030006031327c0006fec078ae3;
        mem[650] = 128'h0ff87813fbf6081300158c1303700893;
        mem[651] = 128'h6b88889300281813100008b7fd08e6e3;
        mem[652] = 128'h0015c603000800670008280301180833;
        mem[653] = 128'h0ff8f893fd0608930015881300900713;
        mem[654] = 128'h0008059320e6026302a007131d177463;
        mem[655] = 128'h0090081300000693f19ff06f00000713;
        mem[656] = 128'h001717130015859300d7073300269713;
        mem[657] = 128'hfd060713fd0706930005c60300c70733;
        mem[658] = 128'h00092683eddff06ffce87ee30ff77713;
        mem[659] = 128'hec06d4e3002305930049091300234603;
        mem[660] = 128'h0407e793ebdff06f0107e79340d006b3;
        mem[661] = 128'ha71ff0ef004909130009258301000613;
        mem[662] = 128'hdf9ff06fde0792e3001c0313001c4783;
        mem[663] = 128'h00058c13fddff06f00a0061300058c13;
        mem[664] = 128'h000645831a0606630049091300092603;
        mem[665] = 128'h0006071300e608b35a0588630107f793;
        mem[666] = 128'hfe059ae3001707130017458301170a63;
        mem[667] = 128'h031052631c07846340c888b300070893;
        mem[668] = 128'h001606130006470300050793011605b3;
        mem[669] = 128'h01150533feb618e3fee78fa300178793;
        mem[670] = 128'h00050793001c031300e5073341168733;
        mem[671] = 128'hfec78fa30017879300d8dc6302000613;
        mem[672] = 128'h001c47834116853300d506b3fee79ce3;
        mem[673] = 128'hfff0061300058c13d51ff06fd2079ee3;
        mem[674] = 128'h00490913010006130009258310c68463;
        mem[675] = 128'hd00798e3001c0313001c478399dff0ef;
        mem[676] = 128'hf09ff06f0080061300058c13d25ff06f;
        mem[677] = 128'h001c0313004905930107f79300058c13;
        mem[678] = 128'h0010081300150613000927830e078263;
        mem[679] = 128'h0006079300d505330200071300f50023;
        mem[680] = 128'hfea79ce3fee78fa3001787934ed85263;
        mem[681] = 128'h00058913001c478300d60533fff68693;
        mem[682] = 128'h0000089300070593cc1ff06fca0796e3;
        mem[683] = 128'h00171713001808130117073300289713;
        mem[684] = 128'hfd060713fd0708930008460300c70733;
        mem[685] = 128'h41f75713fff8c713fce5fee30ff77713;
        mem[686] = 128'h00092703d25ff06f00e8f73300080593;
        mem[687] = 128'h41f85813fff74813004909130025c603;
        mem[688] = 128'h000c4783d05ff06f0025859301077733;
        mem[689] = 128'h001c031300150513001c478300f50023;
        mem[690] = 128'h008006930017e793c41ff06fc20796e3;
        mem[691] = 128'h510606130107f79310000637ef5ff06f;
        mem[692] = 128'hfff687133cd7d86300100793e59ff06f;
        mem[693] = 128'h00178793020006130005079300e50733;
        mem[694] = 128'hfff5051300092783fee79ce3fec78fa3;
        mem[695] = 128'hf1dff06f0015051300f5002300d50533;
        mem[696] = 128'h0005079300e50733411687333ad8da63;
        mem[697] = 128'hfee79ce3feb78fa30017879302000593;
        mem[698] = 128'he11ff06ffff886934116853300d506b3;
        mem[699] = 128'hdac30ce3004908130027e79306c00613;
        mem[700] = 128'hd91ff06f0008091300a0061300092583;
        mem[701] = 128'h0049091300092e0330e3006306c00713;
        mem[702] = 128'h000003130010071326060663000e4603;
        mem[703] = 128'h51eb85b724c5d2630630059300000893;
        mem[704] = 128'h1000083706400e9302b635b351f58593;
        mem[705] = 128'h00270733ccdf0f13ccccdf374c080813;
        mem[706] = 128'h0005cf8300b805b303d58eb30055d593;
        mem[707] = 128'h41d605b301f5842300288893002885b3;
        mem[708] = 128'h000ecf0300c80eb30036561303e5b633;
        mem[709] = 128'h01e704230016161300ce863300261e93;
        mem[710] = 128'h002886330007458300c8073340c58633;
        mem[711] = 128'h001887130040061300b6042300130313;
        mem[712] = 128'h002705b300064603006e063302c30e63;
        mem[713] = 128'h00270713001708930105842302e00813;
        mem[714] = 128'h00c88423002888b303000613f4061ae3;
        mem[715] = 128'h0107f793fcc316e30040061300130313;
        mem[716] = 128'h00c5063340e6863326d75c6302079863;
        mem[717] = 128'hfeb78fa3001787930200059300050793;
        mem[718] = 128'hfff7069340e6853300d506b3fec79ce3;
        mem[719] = 128'h0007c60300e505b30081079302e05063;
        mem[720] = 128'hfeb518e3fec50fa30017879300150513;
        mem[721] = 128'h0200079300e5073340e68733c4d758e3;
        mem[722] = 128'hc35ff06ffee51ce3fef50fa300150513;
        mem[723] = 128'h10000737eae310e30407e79306c00713;
        mem[724] = 128'h00000313004909134e87071300092e83;
        mem[725] = 128'h0100006f03a00f1300600e1300000893;
        mem[726] = 128'h006e86330038889301e6042300260633;
        mem[727] = 128'h00465813001303130018829300064603;
        mem[728] = 128'h00c7063300084f8300f6761301070833;
        mem[729] = 128'h0022863301f604230028863300064803;
        mem[730] = 128'h0107f793fbc31ce30028861301060423;
        mem[731] = 128'h0005079300e5073340c6873302079863;
        mem[732] = 128'hff078fa30017879318d65c6302000813;
        mem[733] = 128'h0002869340c6853300d506b3fee79ce3;
        mem[734] = 128'h001505130007c70300c5083300810793;
        mem[735] = 128'h00080513ff0518e3fee50fa300178793;
        mem[736] = 128'h0200079300c8073340c6863302d65063;
        mem[737] = 128'h00c80533fee51ce3fef50fa300150513;
        mem[738] = 128'h939ff06f920792e3002583130025c783;
        mem[739] = 128'h00900593da1ff06f00058c130407e793;
        mem[740] = 128'he19ff06f4c0808131000083702c5c263;
        mem[741] = 128'h0007031300c104230010071303000613;
        mem[742] = 128'h02b635b3ccd58593ccccd5b7e25ff06f;
        mem[743] = 128'h000708934c08081300288eb310000837;
        mem[744] = 128'h002715930005cf0300e805b30035d713;
        mem[745] = 128'h40e6063301ee84230017171300e58733;
        mem[746] = 128'h000500230004051302010413dc5ff06f;
        mem[747] = 128'h4481240344c120838c051ae302014503;
        mem[748] = 128'h47010113000005134401290344412483;
        mem[749] = 128'h4c08071300092e831000083700008067;
        mem[750] = 128'h00058c130027e793e69ff06f00490913;
        mem[751] = 128'hcddff06f00058c13ccdff06f00490813;
        mem[752] = 128'h00058c130407e793a4dff06f00058c13;
        mem[753] = 128'h0015051300092783a41ff06f01000613;
        mem[754] = 128'h820790e3001c4783fef50fa300058913;
        mem[755] = 128'hfff68693a85ff06ffff68693835ff06f;
        mem[756] = 128'h001c0313a8079ce300000893db1ff06f;
        mem[757] = 128'hfff68693ab9ff06f001c4783c2d04ae3;
        mem[758] = 128'h00000000b31ff06f00060513e81ff06f;
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
        mem[0] = 128'h722065636e616d726f66726570206b36;
        mem[1] = 128'h6f662073726574656d61726170206e75;
        mem[2] = 128'h000000000a2e6b72616d65726f632072;
        mem[3] = 128'h7572206e6f69746164696c6176206b36;
        mem[4] = 128'h726f662073726574656d61726170206e;
        mem[5] = 128'h666f7250000a2e6b72616d65726f6320;
        mem[6] = 128'h72206e6f69746172656e656720656c69;
        mem[7] = 128'h6f662073726574656d61726170206e75;
        mem[8] = 128'h000000000a2e6b72616d65726f632072;
        mem[9] = 128'h722065636e616d726f66726570204b32;
        mem[10] = 128'h6f662073726574656d61726170206e75;
        mem[11] = 128'h000000000a2e6b72616d65726f632072;
        mem[12] = 128'h7572206e6f69746164696c6176204b32;
        mem[13] = 128'h726f662073726574656d61726170206e;
        mem[14] = 128'h5d75255b000a2e6b72616d65726f6320;
        mem[15] = 128'h20637263207473696c2021524f525245;
        mem[16] = 128'h20646c756f6873202d20783430257830;
        mem[17] = 128'h5d75255b00000a783430257830206562;
        mem[18] = 128'h72632078697274616d2021524f525245;
        mem[19] = 128'h6c756f6873202d207834302578302063;
        mem[20] = 128'h000000000a7834302578302065622064;
        mem[21] = 128'h65746174732021524f5252455d75255b;
        mem[22] = 128'h6873202d207834302578302063726320;
        mem[23] = 128'h000a78343025783020656220646c756f;
        mem[24] = 128'h202020657a6953206b72614d65726f43;
        mem[25] = 128'h6974206c61746f54000a756c25203a20;
        mem[26] = 128'h000a756c25203a202020202020736b63;
        mem[27] = 128'h736365732820656d6974206c61746f54;
        mem[28] = 128'h6f6974617265744900000a6425203a29;
        mem[29] = 128'h00000a6425203a2020206365532f736e;
        mem[30] = 128'h63657865207473754d2021524f525245;
        mem[31] = 128'h747361656c20746120726f6620657475;
        mem[32] = 128'h76206120726f66207363657320303120;
        mem[33] = 128'h0000000a21746c757365722064696c61;
        mem[34] = 128'h202020202020736e6f69746172657449;
        mem[35] = 128'h2e322e3431434347000a756c25203a20;
        mem[36] = 128'h7265762072656c69706d6f4300000030;
        mem[37] = 128'h3233767200000a7325203a206e6f6973;
        mem[38] = 128'h00000000324f2d20727363697a5f6d69;
        mem[39] = 128'h20207367616c662072656c69706d6f43;
        mem[40] = 128'h000000004d454d4400000a7325203a20;
        mem[41] = 128'h206e6f697461636f6c2079726f6d654d;
        mem[42] = 128'h206372636465657300000a7325203a20;
        mem[43] = 128'h3430257830203a202020202020202020;
        mem[44] = 128'h207473696c6372635d64255b00000a78;
        mem[45] = 128'h000a783430257830203a202020202020;
        mem[46] = 128'h20202078697274616d6372635d64255b;
        mem[47] = 128'h5d64255b000a783430257830203a2020;
        mem[48] = 128'h203a2020202020206574617473637263;
        mem[49] = 128'h666372635d64255b000a783430257830;
        mem[50] = 128'h30257830203a2020202020206c616e69;
        mem[51] = 128'h7265706f2074636572726f43000a7834;
        mem[52] = 128'h2e6465746164696c6176206e6f697461;
        mem[53] = 128'h6620646d2e454d444145522065655320;
        mem[54] = 128'h726f70657220646e61206e757220726f;
        mem[55] = 128'h000000000a2e73656c757220676e6974;
        mem[56] = 128'h2065746164696c617620746f6e6e6143;
        mem[57] = 128'h687420726f66206e6f6974617265706f;
        mem[58] = 128'h2c7365756c6176206465657320657365;
        mem[59] = 128'h20657261706d6f6320657361656c7020;
        mem[60] = 128'h206e6f2073746c757365722068746977;
        mem[61] = 128'h6d726f6674616c70206e776f6e6b2061;
        mem[62] = 128'h63657465642073726f72724500000a2e;
        mem[63] = 128'h0000636974617453000000000a646574;
        mem[64] = 128'h0000006b636174530000000070616548;
        mem[65] = 128'h542e542d0000000046312d65332e3054;
        mem[66] = 128'h7a3465342e3354310000000071542b2b;
        mem[67] = 128'h000000005e542d65302e343300000000;
        mem[68] = 128'h32312e2d00000000332b653030352e35;
        mem[69] = 128'h3233382b6537382d00000000322d6533;
        mem[70] = 128'h0000000032312d65362e302b00000000;
        mem[71] = 128'h3332312e0000000030303434352e3533;
        mem[72] = 128'h3030372e3031312d0000000030303534;
        mem[73] = 128'h0000000030303434362e302b00000000;
        mem[74] = 128'h00000000343332310000000032313035;
        mem[75] = 128'h000000003232312b000000003437382d;
        mem[76] = 128'h66656463626139383736353433323130;
        mem[77] = 128'h767574737271706f6e6d6c6b6a696867;
        mem[78] = 128'h3736353433323130000000007a797877;
        mem[79] = 128'h4e4d4c4b4a4948474645444342413938;
        mem[80] = 128'h000000005a595857565554535251504f;
        mem[81] = 128'he7146a793340d4b000003e4c4c554e3c;
        mem[82] = 128'h000007471fd756081199be520000e3c1;
        mem[83] = 128'h100004a000008d848e3ae5a439bf5e47;
        mem[84] = 128'h10000470100004b8100004b0100004a8;
        mem[85] = 128'h1000044010000494100004881000047c;
        mem[86] = 128'h1000041010000464100004581000044c;
        mem[87] = 128'h000020d410000434100004281000041c;
        mem[88] = 128'h000020c8000020bc000020b0000020a4;
        mem[89] = 128'h000027ec000027ec0000286c00002098;
        mem[90] = 128'h000027ec000027ec000027ec00002860;
        mem[91] = 128'h000027ec000027ec000027ec000027ec;
        mem[92] = 128'h000027ec00002848000027ec00002854;
        mem[93] = 128'h0000287800002e300000283c000027ec;
        mem[94] = 128'h00002878000028780000287800002878;
        mem[95] = 128'h00002878000028780000287800002878;
        mem[96] = 128'h00002878000028780000287800002878;
        mem[97] = 128'h00002878000028780000287800002878;
        mem[98] = 128'h00002878000028780000287800002878;
        mem[99] = 128'h000028780000287800002f0800002878;
        mem[100] = 128'h00002878000028780000287800002878;
        mem[101] = 128'h0000287800002ef80000287800002878;
        mem[102] = 128'h000028780000287800002ee800002a50;
        mem[103] = 128'h0000287800002ee80000287800002878;
        mem[104] = 128'h00002878000028780000287800002878;
        mem[105] = 128'h000028780000287800002a1800002a44;
        mem[106] = 128'h0000287800002970000028780000297c;
        mem[107] = 128'h0000287c00002d3000002f0000002878;
        mem[108] = 128'h0000287c0000287c0000287c0000287c;
        mem[109] = 128'h0000287c0000287c0000287c0000287c;
        mem[110] = 128'h0000287c0000287c0000287c0000287c;
        mem[111] = 128'h0000287c0000287c0000287c0000287c;
        mem[112] = 128'h0000287c0000287c0000287c0000287c;
        mem[113] = 128'h0000287c0000287c0000294c0000287c;
        mem[114] = 128'h0000287c0000287c0000287c0000287c;
        mem[115] = 128'h0000287c00002bd00000287c0000287c;
        mem[116] = 128'h0000287c0000287c00002bb000002a54;
        mem[117] = 128'h0000287c00002bb00000287c0000287c;
        mem[118] = 128'h0000287c0000287c0000287c0000287c;
        mem[119] = 128'h0000287c0000287c00002a1c00002a48;
        mem[120] = 128'h0000287c000029740000287c00002980;
        mem[121] = 128'h0000000100000001000029500000287c;
        mem[122] = 128'h00000000000000000000000000000066;
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
