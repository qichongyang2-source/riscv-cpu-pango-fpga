# -*- coding: utf-8 -*-
"""flatten.py : 把全部 RTL 合并成单个 Verilog 文件，便于在只支持单文件的环境导入

用法：
    python flatten.py [-o 输出文件] [--top fpga_top]
默认输出 代码/rtl_flat/riscv_soc_flat.v
"""
import argparse
import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CODE = os.path.dirname(os.path.dirname(HERE))   # 代码/
RTL = os.path.join(CODE, 'rtl')

# 按依赖顺序排列（被引用的模块在前）
ORDER = [
    'core/riscv_defs.vh',
    'core/riscv_alu.v',
    'core/riscv_regfile.v',
    'core/riscv_lsu.v',
    'core/riscv_decoder.v',
    'core/riscv_hazard.v',
    'core/riscv_csr.v',
    'core/riscv_divider.v',
    'core/riscv_mul.v',
    'core/riscv_btb.v',
    'core/riscv_core.v',
    'mem/imem.v',
    'mem/dmem.v',
    'mem/icache.v',
    'mem/dcache.v',
    'ai/ai_accel.v',
    'periph/uart_tx.v',
    'periph/uart_rx.v',
    'periph/gpio.v',
    'periph/timer.v',
    'soc/soc_top.v',
    'soc/fpga_top.v',
]


def read_clean(path):
    text = io.open(path, encoding='utf-8', errors='ignore').read()
    text = text.replace('\ufeff', '')
    out = []
    for line in text.splitlines():
        st = line.strip()
        if st.startswith('`timescale'):
            continue
        if st.startswith('`include'):
            continue
        out.append(line)
    return '\n'.join(out).strip('\n')


def defs_body(path):
    """去掉 include guard，只保留宏定义"""
    text = read_clean(path)
    lines = []
    for line in text.splitlines():
        st = line.strip()
        if re.match(r'`(ifndef|define)\s+RISCV_DEFS_VH', st):
            continue
        if st == '`endif' and line == text.splitlines()[-1]:
            continue
        lines.append(line)
    # 去掉最后一个孤立的 `endif
    while lines and lines[-1].strip() in ('`endif', ''):
        lines.pop()
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', default=os.path.join(CODE, 'rtl_flat', 'riscv_soc_flat.v'))
    ap.add_argument('--top', default='fpga_top')
    args = ap.parse_args()

    parts = []
    parts.append('`timescale 1ns/1ps')
    parts.append('// ==========================================================================')
    parts.append('//  riscv_soc_flat.v : 由 sw/tools/flatten.py 自动生成，请勿手工编辑')
    parts.append('//  包含：RV32I 五级流水 CPU + Cache/主存 + 外设 + AI 加速器 + 板级顶层')
    parts.append('//  顶层模块：%s' % args.top)
    parts.append('// ==========================================================================')
    parts.append('')

    for rel in ORDER:
        path = os.path.join(RTL, rel.replace('/', os.sep))
        if not os.path.exists(path):
            raise SystemExit('missing: %s' % path)
        body = defs_body(path) if rel.endswith('.vh') else read_clean(path)
        parts.append('// --------------------------------------------------------------------------')
        parts.append('//  from: rtl/%s' % rel)
        parts.append('// --------------------------------------------------------------------------')
        parts.append(body)
        parts.append('')

    text = '\n'.join(parts)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    io.open(args.out, 'w', encoding='utf-8').write(text)
    print('wrote %s  (%d lines, %.1f KB)' % (args.out, text.count('\n') + 1,
                                             len(text.encode('utf-8')) / 1024.0))


if __name__ == '__main__':
    main()
