/* ==========================================================================
 *  uart.c : 最小串口输出 + 时钟接口（供 CoreMark / 裸机程序使用）
 * ========================================================================== */
typedef unsigned int   uint32_t;
typedef unsigned long long uint64_t;

#define UART_TX   (*(volatile uint32_t *)0x20000000u)
#define UART_STAT (*(volatile uint32_t *)0x20000004u)

int putchar(int c)
{
    while (UART_STAT & 1u) {
        /* 等待发送完成 */
    }
    UART_TX = (uint32_t)(unsigned char)c;
    return c;
}

int puts(const char *s)
{
    while (*s) {
        putchar(*s++);
    }
    putchar('\n');
    return 0;
}

/* CoreMark 计时接口：mcycle (64 位) */
typedef unsigned long clock_t;

clock_t clock(void)
{
    uint32_t lo, hi;
    __asm__ volatile ("csrr %0, mcycle"  : "=r"(lo));
    __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi));
    return (clock_t)(((uint64_t)hi << 32) | (uint64_t)lo);
}
