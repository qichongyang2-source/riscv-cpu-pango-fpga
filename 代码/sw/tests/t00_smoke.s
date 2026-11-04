# t00_smoke.s : 最小冒烟测试 —— 写测试寄存器退出
    .text
_start:
    li   t0, 0x30000000
    li   t1, 1
    sw   t1, 0(t0)
done:
    j    done
