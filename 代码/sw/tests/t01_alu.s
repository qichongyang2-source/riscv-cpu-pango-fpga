# t01_alu.s : RV32I 算术逻辑指令自测
    .text
_start:
    # ---- 1. addi ----
    li    t6, 1
    li    t0, 5
    addi  t1, t0, -3
    li    t2, 2
    bne   t1, t2, fail

    # ---- 2. add 溢出回绕 ----
    li    t6, 2
    li    t0, 0x7FFFFFFF
    addi  t1, t0, 1
    li    t2, 0x80000000
    bne   t1, t2, fail

    # ---- 3. sub ----
    li    t6, 3
    li    t0, 0x80000000
    addi  t1, t0, -1
    li    t2, 0x7FFFFFFF
    bne   t1, t2, fail

    # ---- 4. sub 寄存器 ----
    li    t6, 4
    li    t0, 100
    li    t2, 42
    sub   t1, t0, t2
    li    t3, 58
    bne   t1, t3, fail

    # ---- 5. and / or / xor ----
    li    t6, 5
    li    t0, 0xF0F0F0F0
    li    t2, 0x0FF00FF0
    and   t1, t0, t2
    li    t3, 0x00F000F0
    bne   t1, t3, fail

    li    t6, 6
    or    t1, t0, t2
    li    t3, 0xFFF0FFF0
    bne   t1, t3, fail

    li    t6, 7
    xor   t1, t0, t2
    li    t3, 0xFF00FF00
    bne   t1, t3, fail

    # ---- 8. xori / andi / ori ----
    li    t6, 8
    li    t0, 0xFF
    xori  t1, t0, -1
    li    t3, 0xFFFFFF00
    bne   t1, t3, fail

    li    t6, 9
    andi  t1, t0, 0x0F
    li    t3, 0x0F
    bne   t1, t3, fail

    li    t6, 10
    ori   t1, t0, 0x300
    li    t3, 0x3FF
    bne   t1, t3, fail

    # ---- 11. sll 立即数 / 寄存器 ----
    li    t6, 11
    li    t0, 1
    slli  t1, t0, 31
    li    t3, 0x80000000
    bne   t1, t3, fail

    li    t6, 12
    li    t2, 4
    li    t0, 0x0F
    sll   t1, t0, t2
    li    t3, 0xF0
    bne   t1, t3, fail

    # ---- 13. srl / sra ----
    li    t6, 13
    li    t0, 0x80000000
    srli  t1, t0, 31
    li    t3, 1
    bne   t1, t3, fail

    li    t6, 14
    li    t0, -8
    srai  t1, t0, 1
    li    t3, -4
    bne   t1, t3, fail

    li    t6, 15
    sra   t1, t0, t2
    li    t3, -1
    bne   t1, t3, fail

    # ---- 16. slt / sltu ----
    li    t6, 16
    li    t0, -1
    li    t2, 0
    slt   t1, t0, t2
    li    t3, 1
    bne   t1, t3, fail

    li    t6, 17
    sltu  t1, t0, t2
    li    t3, 0
    bne   t1, t3, fail

    # ---- 18. slti / sltiu ----
    li    t6, 18
    li    t0, -5
    slti  t1, t0, 0
    li    t3, 1
    bne   t1, t3, fail

    li    t6, 19
    sltiu t1, t0, 0
    li    t3, 0
    bne   t1, t3, fail

    # ---- 20. lui ----
    li    t6, 20
    lui   t1, 0x12345
    li    t3, 0x12345000
    bne   t1, t3, fail

    # ---- 21. auipc ----
    li    t6, 21
auipc_here:
    auipc t1, 0
    la    t3, auipc_here
    bne   t1, t3, fail

    # ---- 22. mv / neg / not / seqz / snez ----
    li    t6, 22
    li    t0, 7
    neg   t1, t0
    li    t3, -7
    bne   t1, t3, fail

    li    t6, 23
    seqz  t1, t0
    li    t3, 0
    bne   t1, t3, fail

    li    t6, 24
    li    t0, 0
    snez  t1, t0
    li    t3, 0
    bne   t1, t3, fail

    j     pass

# ---------------------------------------------------------------- 结果上报
fail:
    li    t0, 0x30000000
    slli  t1, t6, 1          # bit0 = 0 -> FAIL, 高位为错误码
    sw    t1, 0(t0)
fspin:
    j     fspin

pass:
    li    t0, 0x30000000
    li    t1, 1
    sw    t1, 0(t0)
pspin:
    j     pspin
