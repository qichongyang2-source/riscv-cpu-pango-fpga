# t13_trap_ext.s : 向量 mtvec / 外部中断 / 非对齐精确异常 / WFI
    .text
_start:
    la    t0, trap_table
    ori   t0, t0, 1            # mtvec.MODE = 1（向量模式）
    csrw  mtvec, t0

    # ---- 1. WFI 按 NOP 执行 ----
    li    t6, 1
    wfi
    li    t1, 0x11
    addi  t2, t1, 1
    li    t3, 0x12
    bne   t2, t3, fail

    # ---- 2. 外部中断：向量入口 base + 4*11 ----
    li    t6, 2
    li    t0, 0x20003000
    li    t1, 1
    sw    t1, 0(t0)            # 拉起 MEIP（软件中断寄存器）
    li    t1, 0x800            # MEIE
    csrs  mie, t1
    li    s0, 0
    li    t1, 8
    csrs  mstatus, t1          # 最后开 MIE
wait_ext:
    beq   s0, x0, wait_ext
    li    t1, 11
    bne   s0, t1, fail

    # ---- 3. 非对齐 LW：cause 4 ----
    li    t6, 3
    li    t0, 0x10000000
    li    t1, 0x11223344
    sw    t1, 0(t0)
    li    s0, 0
    lw    t2, 1(t0)            # 触发异常，handler 跳过
    li    t1, 4
    bne   s0, t1, fail

    # ---- 4. 非对齐 SW：cause 6 ----
    li    t6, 4
    li    t0, 0x10000000
    li    t1, 0x11223344
    li    s0, 0
    sw    t1, 2(t0)
    li    t1, 6
    bne   s0, t1, fail

    # ---- 5. 非对齐 LH：cause 4 ----
    li    t6, 5
    li    t0, 0x10000000
    li    s0, 0
    lh    t2, 1(t0)
    li    t1, 4
    bne   s0, t1, fail

    # ---- 6. 异常后仍可正常访存 ----
    li    t6, 6
    li    t0, 0x10000000
    lw    t2, 0(t0)
    li    t3, 0x11223344
    bne   t2, t3, fail

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

# ---------------------------------------------------------------- 向量表
    .align 8
trap_table:
    j     exc_entry          # cause 0  (offset 0)
    .word 0                  # 1
    .word 0                  # 2
    .word 0                  # 3
    .word 0                  # 4
    .word 0                  # 5
    .word 0                  # 6
    j     exc_entry          # cause 7  (offset 28)
    .word 0                  # 8
    .word 0                  # 9
    .word 0                  # 10
    j     ext_entry          # cause 11 (offset 44)

# ---------------------------------------------------------------- 同步异常
exc_entry:
    csrr  s0, mcause
    andi  s0, s0, 0x1f
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret

# ---------------------------------------------------------------- 外部中断
ext_entry:
    csrr  s0, mcause
    andi  s0, s0, 0x7ff
    li    t0, 0x20003000
    sw    x0, 0(t0)            # 清中断源
    li    t1, 0x800
    csrc  mie, t1              # 关 MEIE
    mret
