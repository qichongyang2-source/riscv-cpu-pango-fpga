# t07_hazard.s : 流水线冒险专项测试
    .text
_start:
    # ---- 1. 连续 ALU 依赖链（EX/MEM 转发） ----
    li    t6, 1
    li    a0, 1
    add   a1, a0, a0           # 2
    add   a2, a1, a0           # 3
    add   a3, a2, a1           # 5
    add   a4, a3, a2           # 8
    li    t0, 8
    bne   a4, t0, fail

    # ---- 2. 距离 3 的 RAW（WB->ID 旁路） ----
    li    t6, 2
    li    a0, 0x10
    nop
    add   a1, a0, a0           # 0x20
    li    t0, 0x20
    bne   a1, t0, fail

    # ---- 3. load-use 停顿 ----
    li    t6, 3
    li    t0, 0x10000000
    li    t1, 0x1234
    sw    t1, 0(t0)
    lw    a1, 0(t0)
    addi  a2, a1, 1            # 需要停顿
    li    t3, 0x1235
    bne   a2, t3, fail

    # ---- 4. store 数据转发 ----
    li    t6, 4
    li    a1, 0x77
    sw    a1, 4(t0)
    lw    a2, 4(t0)
    bne   a2, a1, fail

    # ---- 5. 分支依赖 load ----
    li    t6, 5
    lw    a1, 0(t0)
    li    a3, 0x1234
    beq   a1, a3, h5_ok
    j     fail
h5_ok:

    # ---- 6. jalr 依赖 ALU 结果 ----
    li    t6, 6
    la    a1, target6
    addi  a1, a1, 0
    jalr  ra, a1, 0
    j     fail
target6:

    # ---- 7. CSR 写后读互锁 ----
    li    t6, 7
    li    a1, 0x99
    addi  a1, a1, 1
    csrw  mscratch, a1
    csrr  a2, mscratch
    li    a3, 0x9A
    bne   a2, a3, fail

    # ---- 8. 连续两次写同一寄存器 ----
    li    t6, 8
    li    a0, 1
    addi  a0, a0, 1            # 2
    addi  a0, a0, 1            # 3
    li    t0, 3
    bne   a0, t0, fail

    # ---- 9. 分支目标与顺序执行交错 ----
    li    t6, 9
    li    a0, 0
    beq   x0, x0, h9_taken
    addi  a0, a0, 1
h9_taken:
    addi  a0, a0, 2
    li    t0, 2
    bne   a0, t0, fail

    # ---- 10. load 后立即 store 同一寄存器 ----
    li    t6, 10
    li    t0, 0x10000000
    lw    a1, 0(t0)
    sw    a1, 8(t0)
    lw    a2, 8(t0)
    bne   a2, a1, fail

    j     pass

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
