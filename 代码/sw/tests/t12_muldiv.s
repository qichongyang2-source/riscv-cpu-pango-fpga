# t12_muldiv.s : M 扩展（乘除法）自测
    .text
_start:
    # ---- 1. MUL ----
    li    t6, 1
    li    a0, 7
    li    a1, 6
    mul   a2, a0, a1
    li    t0, 42
    bne   a2, t0, fail

    li    t6, 2
    li    a0, -7
    li    a1, 6
    mul   a2, a0, a1
    li    t0, -42
    bne   a2, t0, fail

    # ---- 3. MUL 低 32 位回绕 ----
    li    t6, 3
    li    a0, 0x80000000
    li    a1, 2
    mul   a2, a0, a1
    bne   a2, x0, fail

    # ---- 4. MULH: (-1)*(-1) 高 32 位 = 0 ----
    li    t6, 4
    li    a0, -1
    li    a1, -1
    mulh  a2, a0, a1
    bne   a2, x0, fail

    # ---- 5. MULH: 0x40000000 * 4 = 0x1_00000000 ----
    li    t6, 5
    li    a0, 0x40000000
    li    a1, 4
    mulh  a2, a0, a1
    li    t0, 1
    bne   a2, t0, fail

    # ---- 6. MULHU: 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001 ----
    li    t6, 6
    li    a0, -1
    li    a1, -1
    mulhu a2, a0, a1
    li    t0, 0xFFFFFFFE
    bne   a2, t0, fail
    mul   a3, a0, a1
    li    t0, 1
    bne   a3, t0, fail

    # ---- 7. MULHSU: 0xFFFFFFFF(-1) * 2 = 0xFFFFFFFF_FFFFFFFE ----
    li    t6, 7
    li    a0, -1
    li    a1, 2
    mulhsu a2, a0, a1
    li    t0, 0xFFFFFFFF
    bne   a2, t0, fail

    # ---- 8. DIV 正数 ----
    li    t6, 8
    li    a0, 20
    li    a1, 6
    div   a2, a0, a1
    li    t0, 3
    bne   a2, t0, fail

    # ---- 9. DIV 负数截断 ----
    li    t6, 9
    li    a0, -20
    li    a1, 6
    div   a2, a0, a1
    li    t0, -3
    bne   a2, t0, fail

    # ---- 10. DIV 除零 = -1 ----
    li    t6, 10
    li    a0, 123
    li    a1, 0
    div   a2, a0, a1
    li    t0, -1
    bne   a2, t0, fail

    # ---- 11. DIV 溢出 (-2^31 / -1) ----
    li    t6, 11
    li    a0, 0x80000000
    li    a1, -1
    div   a2, a0, a1
    li    t0, 0x80000000
    bne   a2, t0, fail

    # ---- 12. DIVU ----
    li    t6, 12
    li    a0, -1
    li    a1, 2
    divu  a2, a0, a1
    li    t0, 0x7FFFFFFF
    bne   a2, t0, fail

    # ---- 13. REM 符号跟随被除数 ----
    li    t6, 13
    li    a0, -20
    li    a1, 6
    rem   a2, a0, a1
    li    t0, -2
    bne   a2, t0, fail

    li    t6, 14
    li    a0, 20
    li    a1, -6
    rem   a2, a0, a1
    li    t0, 2
    bne   a2, t0, fail

    # ---- 15. REM 除零 = 被除数 ----
    li    t6, 15
    li    a0, 123
    li    a1, 0
    rem   a2, a0, a1
    li    t0, 123
    bne   a2, t0, fail

    # ---- 16. REMU ----
    li    t6, 16
    li    a0, -1
    li    a1, 16
    remu  a2, a0, a1
    li    t0, 15
    bne   a2, t0, fail

    # ---- 17. 连续乘加（转发 + 冻结恢复） ----
    li    t6, 17
    li    a0, 3
    li    a1, 4
    mul   a2, a0, a1
    mul   a3, a2, a2
    div   a4, a3, a2
    li    t0, 12
    bne   a2, t0, fail
    li    t0, 144
    bne   a3, t0, fail
    li    t0, 12
    bne   a4, t0, fail

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
