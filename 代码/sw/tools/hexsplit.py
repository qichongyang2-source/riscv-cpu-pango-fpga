#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hexsplit.py : Intel HEX -> imem.hex / dmem.hex（供 $readmemh 使用）

    python hexsplit.py app.hex -o ../sim/work

规则:
    地址 <  0x0001_0000            -> imem.hex（基址 0）
    地址 >= 0x1000_0000            -> dmem.hex（基址 0x1000_0000）
    其余地址忽略并告警
"""

import argparse
import os
import sys


def parse_ihex(path):
    mem = {}
    base = 0
    with open(path, 'r', encoding='ascii') as f:
        for line in f:
            line = line.strip()
            if not line or line[0] != ':':
                continue
            raw = bytes.fromhex(line[1:])
            count = raw[0]
            addr = (raw[1] << 8) | raw[2]
            rectype = raw[3]
            data = raw[4:4 + count]
            if rectype == 0x00:
                for i, b in enumerate(data):
                    mem[base + addr + i] = b
            elif rectype == 0x01:
                break
            elif rectype == 0x02:
                base = ((data[0] << 8) | data[1]) << 4
            elif rectype == 0x04:
                base = ((data[0] << 8) | data[1]) << 16
            elif rectype in (0x03, 0x05):
                pass
    return mem


def words_from(mem, lo, hi):
    """把 [lo, hi) 区间按 4 字节小端拼成字，空洞填 0"""
    if not any(lo <= a < hi for a in mem):
        return []
    max_addr = max(a for a in mem if lo <= a < hi)
    nbytes = max_addr - lo + 1
    nwords = (nbytes + 3) // 4
    out = []
    for w in range(nwords):
        val = 0
        for i in range(4):
            a = lo + w * 4 + i
            val |= mem.get(a, 0) << (8 * i)
        out.append(val)
    return out


def write_hex(path, words):
    """每行 4 个字（128 位），高位字在前"""
    n = ((len(words) + 3) // 4) * 4
    if n == 0:
        n = 4
    ws = list(words) + [0] * (n - len(words))
    with open(path, 'w', encoding='ascii') as f:
        for i in range(0, n, 4):
            f.write('%08x%08x%08x%08x\n'
                    % (ws[i + 3] & 0xFFFFFFFF, ws[i + 2] & 0xFFFFFFFF,
                       ws[i + 1] & 0xFFFFFFFF, ws[i] & 0xFFFFFFFF))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ihex')
    ap.add_argument('-o', '--outdir', required=True)
    args = ap.parse_args()

    mem = parse_ihex(args.ihex)
    if not mem:
        print('error: empty hex file', file=sys.stderr)
        return 1

    imem = words_from(mem, 0x00000000, 0x00010000)
    dmem = words_from(mem, 0x10000000, 0x10010000)
    other = [a for a in mem if not (0 <= a < 0x10000 or 0x10000000 <= a < 0x10010000)]
    if other:
        print('warning: %d bytes outside IMEM/DMEM, ignored (first=0x%08x)'
              % (len(other), other[0]), file=sys.stderr)

    os.makedirs(args.outdir, exist_ok=True)
    write_hex(os.path.join(args.outdir, 'imem.hex'), imem)
    write_hex(os.path.join(args.outdir, 'dmem.hex'), dmem)
    print('ihex -> %s : imem %d words, dmem %d words'
          % (args.outdir, len(imem), len(dmem)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
