# t09_periph.s : GPIO / 定时器 外设寄存器访问测试
    .text
_start:
    # ---- 1. GPIO 输出/方向寄存器 ----
    li    t6, 1
    li    t0, 0x20001000
    li    t1, 0x0000A5A5
    sw    t1, 0(t0)            # gpio_out
    li    t2, 0x0000000F
    sw    t2, 8(t0)            # gpio_oe
    lw    t3, 0(t0)            # 读回 out
    bne   t3, t1, fail
    lw    t3, 8(t0)            # 读回 oe
    bne   t3, t2, fail

    # ---- 2. 定时器 mtime 递增 ----
    li    t6, 2
    li    t0, 0x20002000
    lw    t1, 0(t0)
    nop
    nop
    nop
    lw    t2, 0(t0)
    blt   t1, t2, t2_ok
    j     fail
t2_ok:

    # ---- 3. mtimecmp 读写 ----
    li    t6, 3
    li    t1, 0x12345678
    sw    t1, 8(t0)
    lw    t2, 8(t0)
    bne   t2, t1, fail

    # ---- 4. UART 发送一个字节（'U' = 0x55），随后读状态 ----
    li    t6, 4
    li    t3, 0x20000000
    li    t1, 0x55
    sw    t1, 0(t3)
    li    t4, 100
t4_wait:
    lw    t2, 4(t3)            # bit0 = tx_busy
    andi  t2, t2, 1
    beq   t2, x0, t4_done
    addi  t4, t4, -1
    bne   t4, x0, t4_wait
    j     fail
t4_done:

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
