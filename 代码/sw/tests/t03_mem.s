# t03_mem.s : 访存指令自测（字节/半字/字、符号扩展、非对齐、转发）
    .text
_start:
    li    t0, 0x10000000

    # ---- 1. SW / LW ----
    li    t6, 1
    li    t1, 0x12345678
    sw    t1, 0(t0)
    lw    t2, 0(t0)
    bne   t2, t1, fail

    # ---- 2. 偏移寻址 ----
    li    t6, 2
    li    t1, 0xAABBCCDD
    sw    t1, 4(t0)
    lw    t2, 4(t0)
    bne   t2, t1, fail
    lw    t2, 0(t0)
    li    t3, 0x12345678
    bne   t2, t3, fail

    # ---- 3. SB + LB 符号扩展 ----
    li    t6, 3
    li    t1, 0xFF
    sb    t1, 8(t0)
    lb    t2, 8(t0)
    li    t3, -1
    bne   t2, t3, fail

    # ---- 4. LBU 零扩展 ----
    li    t6, 4
    lbu   t2, 8(t0)
    li    t3, 0xFF
    bne   t2, t3, fail

    # ---- 5. SH + LH 符号扩展 ----
    li    t6, 5
    li    t1, 0x8001
    sh    t1, 10(t0)
    lh    t2, 10(t0)
    li    t3, 0xFFFF8001
    bne   t2, t3, fail

    # ---- 6. LHU 零扩展 ----
    li    t6, 6
    lhu   t2, 10(t0)
    li    t3, 0x00008001
    bne   t2, t3, fail

    # ---- 7. 奇数地址字节访问 ----
    li    t6, 7
    li    t1, 0x5A
    sb    t1, 13(t0)
    lbu   t2, 13(t0)
    li    t3, 0x5A
    bne   t2, t3, fail
    sb    t1, 15(t0)
    lbu   t2, 15(t0)
    bne   t2, t3, fail

    # ---- 8. 半字（2 字节对齐） ----
    li    t6, 8
    li    t1, 0xBEEF
    sh    t1, 18(t0)
    lhu   t2, 18(t0)
    li    t3, 0xBEEF
    bne   t2, t3, fail

    # ---- 9. load-use 冒险（停顿 1 拍） ----
    li    t6, 9
    li    t1, 0x11112222
    sw    t1, 24(t0)
    lw    t2, 24(t0)
    addi  t3, t2, 1
    li    t4, 0x11112223
    bne   t3, t4, fail

    # ---- 10. store 数据转发 ----
    li    t6, 10
    li    t1, 0x55
    sw    t1, 28(t0)
    lw    t2, 28(t0)
    bne   t2, t1, fail

    # ---- 11. 连续读写同一地址 ----
    li    t6, 11
    li    t1, 0xDEADBEEF
    sw    t1, 32(t0)
    lw    t2, 32(t0)
    lw    t3, 32(t0)
    bne   t2, t1, fail
    bne   t3, t1, fail

    # ---- 12. 字节写不破坏相邻字节 ----
    li    t6, 12
    li    t1, 0x00000000
    sw    t1, 36(t0)
    li    t1, 0xA5
    sb    t1, 37(t0)
    lw    t2, 36(t0)
    li    t3, 0x0000A500
    bne   t2, t3, fail

    # ---- 13. DMEM 与 IMEM 地址空间隔离 ----
    li    t6, 13
    li    t1, 0x0BADF00D
    sw    t1, 0(t0)
    lw    t2, 0(t0)
    bne   t2, t1, fail

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
