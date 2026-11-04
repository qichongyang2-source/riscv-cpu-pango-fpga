`timescale 1ns/1ps
//=============================================================================
//  riscv_core.v : RV32I 五级流水线处理器内核
//  IF -> ID -> EX -> MEM -> WB
//  - 全转发 + load-use 停顿
//  - 分支/跳转在 EX 级解决（静态预测不跳转，跳转时清空 2 条指令）
//  - CSR / 异常 / 机器定时器中断 / mret
//  - 指令与数据接口均为组合读（便于映射 LUTRAM；后续可替换为带 I/D Cache
//    的同步 BRAM 版本）
//=============================================================================
`include "riscv_defs.vh"

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
