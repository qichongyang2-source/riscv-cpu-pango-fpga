# t06_sort.s : 冒泡排序集成测试（DMEM 数据段 + 循环 + 访存）
    .text
_start:
    la    s0, array            # 数组首地址
    li    s1, 8                # 元素个数
    addi  s2, s1, -1           # n-1
    li    s3, 0                # i

outer:
    bge   s3, s2, sorted
    li    s4, 0                # j
    sub   s5, s2, s3           # n-1-i
inner:
    bge   s4, s5, next_pass
    slli  t0, s4, 2
    add   t0, t0, s0
    lw    t1, 0(t0)
    lw    t2, 4(t0)
    bge   t2, t1, no_swap
    sw    t2, 0(t0)
    sw    t1, 4(t0)
no_swap:
    addi  s4, s4, 1
    j     inner
next_pass:
    addi  s3, s3, 1
    j     outer

sorted:
    # ---- 1. 校验非递减 ----
    li    t6, 1
    li    s4, 0
    addi  s5, s1, -1
vloop:
    bge   s4, s5, vdone
    slli  t0, s4, 2
    add   t0, t0, s0
    lw    t1, 0(t0)
    lw    t2, 4(t0)
    blt   t2, t1, fail
    addi  s4, s4, 1
    j     vloop
vdone:

    # ---- 2. 校验首尾元素 ----
    li    t6, 2
    lw    t1, 0(s0)
    li    t3, 1
    bne   t1, t3, fail
    slli  t0, s5, 2
    add   t0, t0, s0
    lw    t2, 0(t0)
    li    t3, 9
    bne   t2, t3, fail

    # ---- 3. 校验和 = 39 ----
    li    t6, 3
    li    s6, 0
    li    s4, 0
sloop:
    bge   s4, s1, sdone
    slli  t0, s4, 2
    add   t0, t0, s0
    lw    t1, 0(t0)
    add   s6, s6, t1
    addi  s4, s4, 1
    j     sloop
sdone:
    li    t3, 39
    bne   s6, t3, fail

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

    .data
    .align 2
array:
    .word 5, 3, 9, 1, 7, 2, 8, 4
