    .text
_start:
    la    t0, msg
loop:
    lbu   t1, 0(t0)
    beq   t1, zero, done
    li    t2, 0x20000000
wait:
    lw    t3, 4(t2)
    andi  t3, t3, 1
    bne   t3, zero, wait
    sw    t1, 0(t2)
    addi  t0, t0, 1
    j     loop
done:
    li    t0, 0x30000000
    li    t1, 1
    sw    t1, 0(t0)
spin:
    j     spin

    .data
msg:
    .asciz "Hello from RV32I SoC!\r\n"
