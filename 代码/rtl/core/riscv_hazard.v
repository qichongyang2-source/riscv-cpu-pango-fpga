`timescale 1ns/1ps
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
