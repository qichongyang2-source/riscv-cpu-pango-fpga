# t08_irq.s : 机器定时器中断自测
    .text
_start:
    la    t0, trap_handler
    csrw  mtvec, t0

    # ---- 设定 mtimecmp = mtime + 400 ----
    li    t0, 0x20002000
    lw    t1, 0(t0)            # mtime low
    addi  t1, t1, 400
    sw    t1, 8(t0)            # mtimecmp low
    li    t1, 0
    sw    t1, 12(t0)           # mtimecmp high

    # ---- 使能 MTIE + MIE ----
    li    t1, 0x80
    csrs  mie, t1
    li    t1, 8
    csrs  mstatus, t1

    # ---- 等待中断 ----
    li    s0, 0
    li    s1, 0
wait_irq:
    addi  s1, s1, 1
    beq   s0, x0, wait_irq
    li    t1, 4000
    bge   s1, t1, fail         # 中断没有来

    # ---- 1. mcause = 0x80000007 ----
    li    t6, 1
    li    t1, 0x80000007
    bne   s0, t1, fail

    # ---- 2. 中断服务程序已把 mtimecmp 推远 ----
    li    t6, 2
    li    t0, 0x20002000
    lw    t2, 8(t0)
    li    t3, -1
    bne   t2, t3, fail

    # ---- 3. mstatus.MIE 在 mret 后恢复 ----
    li    t6, 3
    csrr  t0, mstatus
    andi  t0, t0, 8
    beq   t0, x0, fail

    # ---- 4. 关中断后不再触发 ----
    li    t6, 4
    csrc  mstatus, t0
    li    t1, 0x80
    csrc  mie, t1
    li    s0, 0
    li    s2, 0
spin_count:
    addi  s2, s2, 1
    li    t1, 2000
    blt   s2, t1, spin_count
    bne   s0, x0, fail

    j     pass

# ---------------------------------------------------------------- ISR
    .align 2
trap_handler:
    csrr  s0, mcause
    li    t0, 0x20002000
    li    t1, -1
    sw    t1, 8(t0)            # mtimecmp low  = 0xFFFFFFFF
    sw    t1, 12(t0)           # mtimecmp high = 0xFFFFFFFF
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
