/* ==========================================================================
 *  link.ld : RV32I 裸机链接脚本
 *    IMEM : 0x0000_0000  64 KB （代码）
 *    DMEM : 0x1000_0000  64 KB （数据 / 栈 / 堆）
 * ========================================================================== */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw) : ORIGIN = 0x10000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > IMEM

    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > DMEM

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > DMEM

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    end = _bss_end;
}
