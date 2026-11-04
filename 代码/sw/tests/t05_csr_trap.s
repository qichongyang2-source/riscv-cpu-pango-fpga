# t05_csr_trap.s : CSR / 异常 / mret 自测
    .text
_start:
    la    t0, trap_handler
    csrw  mtvec, t0

    # ---- 1. csrw / csrr ----
    li    t6, 1
    li    t1, 0x1234
    csrw  mscratch, t1
    csrr  t2, mscratch
    bne   t2, t1, fail

    # ---- 2. csrs ----
    li    t6, 2
    li    t3, 0x00F0
    csrs  mscratch, t3
    csrr  t2, mscratch
    li    t4, 0x12F4
    bne   t2, t4, fail

    # ---- 3. csrc ----
    li    t6, 3
    csrc  mscratch, t3
    csrr  t2, mscratch
    li    t1, 0x1204
    bne   t2, t1, fail

    # ---- 4. csrrw 返回旧值 ----
    li    t6, 4
    li    t3, 0xABCD
    csrrw t2, mscratch, t3
    bne   t2, t1, fail
    csrr  t2, mscratch
    bne   t2, t3, fail

    # ---- 5. csrrwi ----
    li    t6, 5
    csrwi mscratch, 0x1F
    csrr  t2, mscratch
    li    t4, 0x1F
    bne   t2, t4, fail

    # ---- 6. mstatus.MIE 复位值 0 ----
    li    t6, 6
    csrr  t0, mstatus
    andi  t0, t0, 8
    bne   t0, x0, fail

    # ---- 7. 置位 MIE ----
    li    t6, 7
    li    t1, 8
    csrs  mstatus, t1
    csrr  t0, mstatus
    andi  t0, t0, 8
    bne   t0, t1, fail

    # ---- 8. ecall: mcause = 11 ----
    li    t6, 8
    li    s0, 0
    ecall
    li    t1, 11
    bne   s0, t1, fail

    # ---- 9. mret 后 MIE 恢复为 1 ----
    li    t6, 9
    csrr  t0, mstatus
    andi  t0, t0, 8
    beq   t0, x0, fail

    # ---- 10. ebreak: mcause = 3 ----
    li    t6, 10
    li    s0, 0
    ebreak
    li    t1, 3
    bne   s0, t1, fail

    # ---- 11. 非法指令: mcause = 2, mepc 正确 ----
    li    t6, 11
    li    s0, 0
ill_here:
    .word 0x00000000
    li    t1, 2
    bne   s0, t1, fail
    la    t2, ill_here
    bne   s1, t2, fail

    # ---- 12. 可以继续正常执行 ----
    li    t6, 12
    li    t1, 0x55
    addi  t2, t1, 1
    li    t3, 0x56
    bne   t2, t3, fail

    j     pass

# ---------------------------------------------------------------- trap 入口
    .align 2
trap_handler:
    csrr  s0, mcause
    csrr  s1, mepc
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret

fail:
    li    t0, 0x30000000
    slli  t1, t6, 1
    sw    t1, 0(t0)
fspin:
    j     fspin

pass:
    li    t0, 0x30000000
    li    t1, 1
    sw    t1, 0(t0)
pspin:
    j     pspin
