# t10_cache.s : Cache 专项测试（容量缺失 / 命中 / 写穿）
    .text
_start:
    li    t0, 0x10000000
    li    s0, 1024              # 元素个数（4 KB > 2 KB D-Cache）
    li    s1, 0
    li    s2, 0

# ---- 1. 写满 4 KB（store 全部 miss，写穿到 DMEM） ----
fill_loop:
    slli  t1, s1, 2
    add   t1, t1, t0
    addi  t2, s1, 1
    sw    t2, 0(t1)
    add   s2, s2, t2
    addi  s1, s1, 1
    blt   s1, s0, fill_loop

    li    t6, 1
    li    t3, 524800            # 1+2+...+1024
    bne   s2, t3, fail

# ---- 2. 顺序读回（容量缺失：4 KB 数据 > 2 KB Cache） ----
    li    t6, 2
    li    s1, 0
chk_loop:
    slli  t1, s1, 2
    add   t1, t1, t0
    lw    t2, 0(t1)
    addi  t3, s1, 1
    bne   t2, t3, fail
    addi  s1, s1, 1
    blt   s1, s0, chk_loop

# ---- 3. 重复访问同一地址（应全部命中） ----
    li    t6, 3
    li    s3, 0
    li    s4, 0
    li    t3, 64
rep_loop:
    lw    t2, 0(t0)             # 首元素 = 1
    add   s3, s3, t2
    addi  s4, s4, 1
    blt   s4, t3, rep_loop
    li    t3, 64
    bne   s3, t3, fail

# ---- 4. 字节写命中后再读（写穿 + 行内合并） ----
    li    t6, 4
    li    t1, 0xFFFFFFFF
    sw    t1, 4096(t0)
    li    t1, 0x00
    sb    t1, 4097(t0)          # 第二个字节清零
    lw    t2, 4096(t0)
    li    t3, 0xFFFF00FF
    bne   t2, t3, fail

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
