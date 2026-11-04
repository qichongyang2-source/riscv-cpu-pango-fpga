# t11_conflict.s : Cache 冲突测试（两个 2 KB 间隔数组交替访问）
#   直接映射 2 KB 时两个数组会争用同一组；两路组相联应能同时驻留
    .text
_start:
    li    t0, 0x10000000
    li    t1, 0x10000800        # 与 t0 相差 2 KB，索引位相同
    li    t2, 0x1111
    sw    t2, 0(t0)
    li    t2, 0x2222
    sw    t2, 0(t1)

    li    s0, 0                 # 累加和
    li    s1, 0                 # 循环计数
    li    s2, 64
loop:
    lw    a0, 0(t0)
    lw    a1, 0(t1)
    add   s0, s0, a0
    add   s0, s0, a1
    addi  s1, s1, 1
    blt   s1, s2, loop

    li    t6, 1
    li    t3, 0xCCCC0           # 64 * (0x1111 + 0x2222) = 0x3333 << 6
    bne   s0, t3, fail

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
