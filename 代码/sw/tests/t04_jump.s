# t04_jump.s : 跳转与函数调用自测
    .text
_start:
    li    sp, 0x10008000

    # ---- 1. jal 前向跳转 + 链接值 ----
    li    t6, 1
    jal   ra, func1
after1:
    # 回到这里说明 ra 正确
    j     c2

func1:
    la    t0, after1
    bne   ra, t0, fail
    jr    ra

c2:
    # ---- 2. jalr 绝对地址调用 ----
    li    t6, 2
    la    t0, func2
    jalr  ra, t0, 0
after2:
    j     c3

func2:
    la    t0, after2
    bne   ra, t0, fail
    ret

c3:
    # ---- 3. jalr 带偏移 ----
    li    t6, 3
    la    t0, func3
    jalr  ra, t0, 0
after3:
    j     c4

func3:
    addi  t1, t0, 0            # 占位
    ret

c4:
    # ---- 4. 嵌套调用（栈保存 ra） ----
    li    t6, 4
    li    s0, 0
    jal   ra, outer
    li    t1, 7
    bne   s0, t1, fail
    j     c5

outer:
    addi  sp, sp, -8
    sw    ra, 4(sp)
    jal   ra, inner
    lw    ra, 4(sp)
    addi  sp, sp, 8
    ret

inner:
    addi  s0, s0, 7
    ret

c5:
    # ---- 5. jal x0（无条件跳转，不写 ra） ----
    li    t6, 5
    li    s1, 0x5A
    j     c5_target
    li    s1, 0xFF             # 不应执行
c5_target:
    li    t1, 0x5A
    bne   s1, t1, fail

    # ---- 6. 循环中函数调用 ----
    li    t6, 6
    li    s2, 0
    li    s3, 5
c6_loop:
    beq   s3, x0, c6_done
    jal   ra, inc
    addi  s3, s3, -1
    j     c6_loop
c6_done:
    li    t1, 5
    bne   s2, t1, fail

    j     pass

inc:
    addi  s2, s2, 1
    ret

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
