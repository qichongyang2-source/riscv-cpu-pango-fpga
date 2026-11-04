/* ==========================================================================
 *  bench.c : 裸机 C 基准程序（验证 C 工具链与内存布局）
 *    1. 素数筛（数组访存 + 分支）
 *    2. 矩阵乘（乘加）
 *    3. CRC32（移位 + 异或）
 *    4. 除法密集循环（M 扩展）
 * ========================================================================== */
typedef unsigned int   uint32_t;
typedef unsigned long  uint64_t;

int putchar(int c);
int puts(const char *s);

#define N 256

static uint32_t sieve[N];
static uint32_t mat_a[16][16];
static uint32_t mat_b[16][16];
static uint32_t mat_c[16][16];

static int fail_code;

static void check(int cond, int code)
{
    if (!cond && !fail_code) {
        fail_code = code;
    }
}

static uint32_t crc32(const unsigned char *p, int n)
{
    uint32_t crc = 0xFFFFFFFFu;
    int i, k;
    for (i = 0; i < n; i++) {
        crc ^= p[i];
        for (k = 0; k < 8; k++) {
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
        }
    }
    return ~crc;
}

int main(void)
{
    int i, j, k;
    uint32_t sum;

    /* ---- 1. 素数筛 ---- */
    for (i = 0; i < N; i++) {
        sieve[i] = 1;
    }
    sieve[0] = 0;
    sieve[1] = 0;
    for (i = 2; i * i < N; i++) {
        if (sieve[i]) {
            for (j = i * i; j < N; j += i) {
                sieve[j] = 0;
            }
        }
    }
    sum = 0;
    for (i = 0; i < N; i++) {
        sum += sieve[i];
    }
    check(sum == 54, 1);          /* 256 以内共 54 个素数 */

    /* ---- 2. 矩阵乘 ---- */
    for (i = 0; i < 16; i++) {
        for (j = 0; j < 16; j++) {
            mat_a[i][j] = (uint32_t)(i + j);
            mat_b[i][j] = (uint32_t)(i * j + 1);
        }
    }
    for (i = 0; i < 16; i++) {
        for (j = 0; j < 16; j++) {
            uint32_t acc = 0;
            for (k = 0; k < 16; k++) {
                acc += mat_a[i][k] * mat_b[k][j];
            }
            mat_c[i][j] = acc;
        }
    }
    check(mat_c[0][0] == 120, 2);
    check(mat_c[15][15] == 45960, 3);

    /* ---- 3. CRC32 ---- */
    {
        const unsigned char msg[] = "123456789";
        uint32_t c = crc32(msg, 9);
        check(c == 0xCBF43926u, 4);
    }

    /* ---- 4. 除法密集 ---- */
    {
        uint32_t acc = 0;
        for (i = 1; i < 200; i++) {
            acc += (uint32_t)(1000000u / (uint32_t)i);
            acc += (uint32_t)(1000000u % (uint32_t)i);
        }
        check(acc == 5882137u, 5);
    }

    puts("BENCH DONE");
    return fail_code;
}
