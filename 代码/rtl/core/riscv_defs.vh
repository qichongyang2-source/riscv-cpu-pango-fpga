//=============================================================================
//  riscv_defs.vh : 全局常量定义 (RV32I 基础整数指令集 + Zicsr)
//  赛题1 : 基于紫光同创 RISC-V 指令集 CPU 设计
//=============================================================================
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

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

`endif
