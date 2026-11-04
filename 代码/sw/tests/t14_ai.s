# t14_ai.s : INT8 矩阵-向量加速器测试（FC / RELU / ARGMAX）
    .text
_start:
    li    s0, 0x20008000        # AI 缓冲基址
    li    s1, 0x20004000        # AI 寄存器基址

    # ---- 准备权重 W（4x4，行优先，INT8）----
    li    t1, 0x04030201        # W[0] = [1,2,3,4]
    sw    t1, 0(s0)
    li    t1, 0x01000100        # W[1] = [0,1,0,1]
    sw    t1, 4(s0)
    li    t1, -1                # W[2] = [-1,-1,-1,-1]
    sw    t1, 8(s0)
    li    t1, 0x02000002        # W[3] = [2,0,0,2]
    sw    t1, 12(s0)

    # ---- 输入 x = [1,2,3,4] ----
    li    t1, 0x04030201
    sw    t1, 16(s0)

    # ---- 配置并启动 FC ----
    li    t1, 0
    sw    t1, 4(s1)             # OP = FC
    li    t1, 4
    sw    t1, 8(s1)             # K = 4
    li    t1, 0
    sw    t1, 16(s1)            # WA = 0
    li    t1, 16
    sw    t1, 20(s1)            # XA = 16
    li    t1, 32
    sw    t1, 24(s1)            # YA = 32
    li    t1, 1
    sw    t1, 0(s1)             # start

wait_fc:
    lw    t2, 0(s1)
    andi  t2, t2, 2             # bit1 = done
    beq   t2, x0, wait_fc

    # ---- 校验 y = [6,1,0,11] ----
    li    t6, 1
    lw    a0, 32(s0)
    li    t3, 6
    bne   a0, t3, fail
    li    t6, 2
    lw    a1, 36(s0)
    li    t3, 1
    bne   a1, t3, fail
    li    t6, 3
    lw    a2, 40(s0)
    bne   a2, x0, fail
    li    t6, 4
    lw    a3, 44(s0)
    li    t3, 11
    bne   a3, t3, fail

    # ---- RELU：[5,-3,9,-7] -> [5,0,9,0] ----
    li    t6, 5
    li    t1, 5
    sw    t1, 64(s0)
    li    t1, -3
    sw    t1, 68(s0)
    li    t1, 9
    sw    t1, 72(s0)
    li    t1, -7
    sw    t1, 76(s0)

    li    t1, 1
    sw    t1, 4(s1)             # OP = RELU
    li    t1, 4
    sw    t1, 12(s1)            # N = 4
    li    t1, 64
    sw    t1, 24(s1)            # YA = 64
    li    t1, 1
    sw    t1, 0(s1)

wait_relu:
    lw    t2, 0(s1)
    andi  t2, t2, 2
    beq   t2, x0, wait_relu

    li    t6, 6
    lw    t3, 64(s0)
    li    t4, 5
    bne   t3, t4, fail
    lw    t3, 68(s0)
    bne   t3, x0, fail
    lw    t3, 72(s0)
    li    t4, 9
    bne   t3, t4, fail
    lw    t3, 76(s0)
    bne   t3, x0, fail

    # ---- ARGMAX：[5,-3,9,2] -> 2 ----
    li    t6, 7
    li    t1, 5
    sw    t1, 96(s0)
    li    t1, -3
    sw    t1, 100(s0)
    li    t1, 9
    sw    t1, 104(s0)
    li    t1, 2
    sw    t1, 108(s0)

    li    t1, 2
    sw    t1, 4(s1)             # OP = ARGMAX
    li    t1, 4
    sw    t1, 12(s1)            # N = 4
    li    t1, 96
    sw    t1, 24(s1)            # YA = 96
    li    t1, 1
    sw    t1, 0(s1)

wait_arg:
    lw    t2, 0(s1)
    andi  t2, t2, 2
    beq   t2, x0, wait_arg

    li    t6, 8
    lw    t3, 36(s1)            # ARG 寄存器
    li    t4, 2
    bne   t3, t4, fail

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
