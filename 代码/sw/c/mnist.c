/* ==========================================================================
 *  mnist.c : 用 AI 加速器做 MNIST 推理（196-32-10 INT8 MLP）
 *
 *  AI 加速器（memory-mapped）：
 *    0x2000_4000 + 4*n : 寄存器（0=CTRL, 1=OP, 2=K, 3=N, 4=WA, 5=XA, 6=YA,
 *                        8=CYC, 9=ARG）
 *    0x2000_8000 + 4*i : 8 KB 本地缓冲
 * ========================================================================== */
#include "mnist_data.h"

#define AI_REG ((volatile unsigned int *)0x20004000u)
#define AI_BUF ((volatile unsigned int *)0x20008000u)
#define AI_U8  ((volatile signed char  *)0x20008000u)

/* 缓冲布局（字节偏移，均 4 字节对齐） */
#define OFF_W1   0
#define OFF_X    6272              /* 196 B */
#define OFF_H    6468              /* 32 x int32 = 128 B */
#define OFF_H8   6596              /* 32 B */
#define OFF_W2   6628              /* 384 B */
#define OFF_LG   7012              /* 12 x int32 */
#define OFF_LG10 7060              /* 10 x int32 */

#define CTRL   0
#define OP     1
#define REG_K  2
#define REG_N  3
#define REG_WA 4
#define REG_XA 5
#define REG_YA 6
#define REG_CY 8
#define REG_AR 9

int putchar(int c);
int puts(const char *s);

static void print_str(const char *s)
{
    while (*s) putchar(*s++);
}

static void print_int(int v)
{
    char b[12];
    int i = 0, neg = 0;
    if (v < 0) { neg = 1; v = -v; }
    if (v == 0) b[i++] = '0';
    while (v > 0) { b[i++] = '0' + (v % 10); v /= 10; }
    if (neg) putchar('-');
    while (i > 0) putchar(b[--i]);
}

static void ai_copy_words(unsigned int off, const void *src, int words)
{
    const unsigned int *p = (const unsigned int *)src;
    volatile unsigned int *d = AI_BUF + (off >> 2);
    int i;
    for (i = 0; i < words; i++) d[i] = p[i];
}

static void ai_wait(void)
{
    int i;
    /* 启动后状态机需要 1 拍清 done，先让流水线走几拍再轮询 */
    for (i = 0; i < 8; i++) __asm__ volatile ("nop");
    while ((AI_REG[CTRL] & 1u) != 0u) {
        /* 等待 busy 落下 */
    }
    while ((AI_REG[CTRL] & 2u) == 0u) {
        /* 等待 done */
    }
}

static void ai_fc(unsigned int k, unsigned int wa, unsigned int xa, unsigned int ya)
{
    AI_REG[OP]    = 0;      /* FC */
    AI_REG[REG_K] = k;
    AI_REG[REG_WA]= wa;
    AI_REG[REG_XA]= xa;
    AI_REG[REG_YA]= ya;
    AI_REG[CTRL]  = 1;      /* start */
    ai_wait();
}

static void ai_argmax(unsigned int n, unsigned int ya)
{
    AI_REG[OP]    = 2;
    AI_REG[REG_N] = n;
    AI_REG[REG_YA]= ya;
    AI_REG[CTRL]  = 1;
    ai_wait();
}

static int run_image(const signed char *img)
{
    int g, j, w;
    unsigned int acc;
    volatile signed char *h8 = (volatile signed char *)(AI_U8 + OFF_H8);

    /* 1. 输入图像 -> 缓冲 */
    ai_copy_words(OFF_X, img, MNIST_IN / 4);

    /* 2. 第一层：8 组 x 4 输出 */
    for (g = 0; g < MNIST_HID / 4; g++)
        ai_fc(MNIST_IN, OFF_W1 + g * MNIST_IN * 4, OFF_X,
              OFF_H + g * 16);

    /* 3. 偏置 + ReLU + 定点缩放 -> INT8 激活 */
    for (j = 0; j < MNIST_HID; j++) {
        int v = (int)AI_BUF[(OFF_H >> 2) + j] + mnist_b1[j];
        if (v < 0) v = 0;
        v = (int)(((long)v * MNIST_M) >> MNIST_SHIFT);
        if (v > 127) v = 127;
        h8[j] = (signed char)v;
    }

    /* 4. 第二层：3 组（最后一组只用到 2 个输出） */
    for (g = 0; g < 3; g++)
        ai_fc(MNIST_HID, OFF_W2 + g * MNIST_HID * 4, OFF_H8,
              OFF_LG + g * 16);

    /* 5. 偏置 + 搬到干净区域 */
    for (j = 0; j < MNIST_OUT; j++) {
        int v = (int)AI_BUF[(OFF_LG >> 2) + j] + mnist_b2[j];
        AI_BUF[(OFF_LG10 >> 2) + j] = (unsigned int)v;
    }

    /* 6. 硬件 ARGMAX */
    ai_argmax(MNIST_OUT, OFF_LG10);
    return (int)AI_REG[REG_AR];
}

int main(void)
{
    int i, pred, correct = 0;

    /* 权重与偏置只搬一次 */
    ai_copy_words(OFF_W1, mnist_w1, sizeof(mnist_w1) / 4);
    ai_copy_words(OFF_W2, mnist_w2, sizeof(mnist_w2) / 4);

    print_str("MNIST inference on AI accelerator\n");

    for (i = 0; i < MNIST_IMGS; i++) {
        pred = run_image(mnist_x[i]);
        if (pred == (int)mnist_label[i]) correct++;
        print_str("  img ");
        print_int(i);
        print_str(": pred ");
        print_int(pred);
        print_str(" label ");
        print_int((int)mnist_label[i]);
        print_str(pred == (int)mnist_label[i] ? "  OK\n" : "  NG\n");
    }

    print_str("correct: ");
    print_int(correct);
    print_str("/");
    print_int(MNIST_IMGS);
    print_str("\n");

    /* 至少 90% 才算通过（20 张图里 <=2 个错） */
    return (correct * 10 >= MNIST_IMGS * 9) ? 0 : 1;
}
