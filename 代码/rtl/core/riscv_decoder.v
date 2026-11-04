`timescale 1ns/1ps
//=============================================================================
//  riscv_decoder.v : RV32I 指令译码 / 控制单元
//  输出控制信号 + 立即数；同时给出非法指令标志与系统指令标志
//=============================================================================
`include "riscv_defs.vh"

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
