# t02_branch.s : 条件分支指令自测
    .text
_start:
    li    t0, 5
    li    t1, 5
    li    t2, 6

    # ---- 1. beq 跳转 ----
    li    t6, 1
    beq   t0, t1, b1_ok
    j     fail
b1_ok:

    # ---- 2. beq 不跳转 ----
    li    t6, 2
    beq   t0, t2, bad2
    j     b2_ok
bad2:
    j     fail
b2_ok:

    # ---- 3. bne 跳转 ----
    li    t6, 3
    bne   t0, t2, b3_ok
    j     fail
b3_ok:

    # ---- 4. bne 不跳转 ----
    li    t6, 4
    bne   t0, t1, bad4
    j     b4_ok
bad4:
    j     fail
b4_ok:

    # ---- 5. blt 有符号跳转 (-1 < 1) ----
    li    t6, 5
    li    t0, -1
    li    t1, 1
    blt   t0, t1, b5_ok
    j     fail
b5_ok:

    # ---- 6. blt 不跳转 (1 < -1) ----
    li    t6, 6
    blt   t1, t0, bad6
    j     b6_ok
bad6:
    j     fail
b6_ok:

    # ---- 7. bge 跳转 ----
    li    t6, 7
    bge   t1, t0, b7_ok
    j     fail
b7_ok:

    # ---- 8. bge 不跳转 ----
    li    t6, 8
    bge   t0, t1, bad8
    j     b8_ok
bad8:
    j     fail
b8_ok:

    # ---- 9. bltu 无符号: 0xFFFFFFFF < 1 不成立 ----
    li    t6, 9
    li    t2, -1
    li    t3, 1
    bltu  t2, t3, bad9
    j     b9_ok
bad9:
    j     fail
b9_ok:

    # ---- 10. bltu 跳转: 1 < 0xFFFFFFFF ----
    li    t6, 10
    bltu  t3, t2, b10_ok
    j     fail
b10_ok:

    # ---- 11. bgeu 跳转 ----
    li    t6, 11
    bgeu  t2, t3, b11_ok
    j     fail
b11_ok:

    # ---- 12. bgeu 不跳转 ----
    li    t6, 12
    bgeu  t3, t2, bad12
    j     b12_ok
bad12:
    j     fail
b12_ok:

    # ---- 13. 跳转延迟槽必须被清空 ----
    li    t6, 13
    li    s11, 0
    beq   x0, x0, b13_ok
    li    s11, 1               # 错误路径，不允许执行
b13_ok:
    bne   s11, x0, fail

    # ---- 14. 上一条 ALU 结果直接作为分支源（EX/MEM 转发） ----
    li    t6, 14
    li    t0, 1
    addi  t0, t0, 4            # t0 = 5
    li    t1, 5
    beq   t0, t1, b14_ok
    j     fail
b14_ok:

    # ---- 15. 后向分支循环 ----
    li    t6, 15
    li    t0, 0
    li    t2, 10
b15_loop:
    addi  t0, t0, 1
    blt   t0, t2, b15_loop
    li    t3, 10
    bne   t0, t3, fail

    # ---- 16. 两层循环嵌套 ----
    li    t6, 16
    li    t0, 0                # 外层计数
    li    t1, 0                # 内层总数
    li    t2, 5
outer16:
    li    t3, 0
    li    t4, 4
inner16:
    addi  t1, t1, 1
    addi  t3, t3, 1
    blt   t3, t4, inner16
    addi  t0, t0, 1
    blt   t0, t2, outer16
    li    t5, 20
    bne   t1, t5, fail

    j     pass

# ---------------------------------------------------------------- 结果上报
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
