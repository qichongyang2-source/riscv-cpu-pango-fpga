#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rvasm.py : 极简 RV32I + Zicsr 汇编器（自带，免交叉工具链）

用法:
    python rvasm.py input.s -o outdir [--hex-only]

输出:
    outdir/imem.hex   指令镜像 ($readmemh 格式, 每行 8 位十六进制)
    outdir/dmem.hex   数据镜像
    outdir/map.txt    符号表 / 反汇编列表

支持:
    - 段: .text (0x0000_0000) / .data (0x1000_0000)
    - 数据: .word .half .byte .string .asciz .space .align .equ/.set
    - RV32I 全部指令 + Zicsr
    - 常用伪指令: li la mv nop not neg seqz snez sltz sgtz beqz bnez
                  blez bgez bltz bgtz j jr ret jal(1参) csrr csrw csrs
                  csrc csrwi
"""

import argparse
import os
import re
import sys

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
TEXT_BASE = 0x00000000
DATA_BASE = 0x10000000
MASK32    = 0xFFFFFFFF

REGS = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15,
    'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23,
    's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
}
for _i in range(32):
    REGS['x%d' % _i] = _i

CSRS = {
    'mstatus': 0x300, 'misa': 0x301, 'mie': 0x304, 'mtvec': 0x305,
    'mscratch': 0x340, 'mepc': 0x341, 'mcause': 0x342, 'mtval': 0x343,
    'mip': 0x344, 'mcycle': 0xB00, 'minstret': 0xB02,
    'mcycleh': 0xB80, 'minstreth': 0xB82,
    'cycle': 0xC00, 'instret': 0xC02, 'cycleh': 0xC80, 'instreth': 0xC82,
    'mvendorid': 0xF11, 'marchid': 0xF12, 'mimpid': 0xF13, 'mhartid': 0xF14,
}

# funct3/funct7 编码表: name -> (fmt, opcode, funct3, funct7)
I = {}
def _d(name, fmt, opcode, funct3=0, funct7=0):
    I[name] = (fmt, opcode, funct3, funct7)

# U 型
_d('lui',   'U', 0x37)
_d('auipc', 'U', 0x17)
# J 型
_d('jal',   'J', 0x6F)
# I 型 (jalr / load / alu imm)
_d('jalr',  'I', 0x67, 0x0)
for _n, _f3 in (('lb', 0), ('lh', 1), ('lw', 2), ('lbu', 4), ('lhu', 5)):
    _d(_n, 'IL', 0x03, _f3)
for _n, _f3 in (('addi', 0), ('slti', 2), ('sltiu', 3), ('xori', 4),
                ('ori', 6), ('andi', 7)):
    _d(_n, 'II', 0x13, _f3)
_d('slli', 'ISH', 0x13, 1, 0x00)
_d('srli', 'ISH', 0x13, 5, 0x00)
_d('srai', 'ISH', 0x13, 5, 0x20)
# S 型
for _n, _f3 in (('sb', 0), ('sh', 1), ('sw', 2)):
    _d(_n, 'S', 0x23, _f3)
# B 型
for _n, _f3 in (('beq', 0), ('bne', 1), ('blt', 4), ('bge', 5),
                ('bltu', 6), ('bgeu', 7)):
    _d(_n, 'B', 0x63, _f3)
# R 型
for _n, _f3, _f7 in (('add', 0, 0x00), ('sub', 0, 0x20), ('sll', 1, 0x00),
                     ('slt', 2, 0x00), ('sltu', 3, 0x00), ('xor', 4, 0x00),
                     ('srl', 5, 0x00), ('sra', 5, 0x20), ('or', 6, 0x00),
                     ('and', 7, 0x00)):
    _d(_n, 'R', 0x33, _f3, _f7)
# M 扩展
for _n, _f3 in (('mul', 0), ('mulh', 1), ('mulhsu', 2), ('mulhu', 3),
                ('div', 4), ('divu', 5), ('rem', 6), ('remu', 7)):
    _d(_n, 'R', 0x33, _f3, 0x01)

# SYSTEM
_d('ecall',  'SYS', 0x73)
_d('ebreak', 'SYS', 0x73)
_d('mret',   'SYS', 0x73)
_d('wfi',    'SYS', 0x73)
_d('fence',  'FENCE', 0x0F, 0)
_d('fence.i','FENCE', 0x0F, 1)
for _n, _f3 in (('csrrw', 1), ('csrrs', 2), ('csrrc', 3),
                ('csrrwi', 5), ('csrrsi', 6), ('csrrci', 7)):
    _d(_n, 'CSR', 0x73, _f3)


class AsmError(Exception):
    pass


def die(msg, ln=None):
    if ln is not None:
        raise AsmError("line %d: %s" % (ln, msg))
    raise AsmError(msg)


# ---------------------------------------------------------------------------
# 词法 / 表达式
# ---------------------------------------------------------------------------
def strip_comment(line):
    out = []
    i = 0
    while i < len(line):
        if line.startswith('//', i) or line[i] in '#;':
            break
        out.append(line[i])
        i += 1
    return ''.join(out)


def parse_reg(tok, ln):
    t = tok.strip().lower()
    if t in REGS:
        return REGS[t]
    die("bad register '%s'" % tok, ln)


def parse_csr(tok, ln):
    t = tok.strip().lower()
    if t in CSRS:
        return CSRS[t]
    return eval_expr(tok, {}, 0, ln) & 0xFFF


def eval_expr(expr, syms, cur_addr, ln):
    e = expr.strip()
    if not e:
        die("empty expression", ln)
    # 当前位置
    e = re.sub(r'(?<![\w.$])\.(?![\w.$])', str(cur_addr), e)
    # 符号替换
    def repl(m):
        name = m.group(0)
        if name in syms:
            return "(%d)" % syms[name]
        if name in ('hi', 'lo'):
            die("bad symbol '%s'" % name, ln)
        die("undefined symbol '%s'" % name, ln)
    e = re.sub(r'\b[A-Za-z_$][\w$]*\b', repl, e)
    # 单斜杠 -> 整除
    e = re.sub(r'(?<!/)/(?!/)', '//', e)
    try:
        v = eval(e, {"__builtins__": {}}, {})
    except Exception:
        die("bad expression '%s'" % expr, ln)
    return int(v) & MASK32


def s32(v):
    v &= MASK32
    return v - (1 << 32) if v & 0x80000000 else v


# ---------------------------------------------------------------------------
# 编码
# ---------------------------------------------------------------------------
def enc_r(f7, rs2, rs1, f3, rd, op):
    return ((f7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((f3 & 7) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 7) << 12) | \
           ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((f3 & 7) << 12) | ((imm & 0x1F) << 7) | (op & 0x7F)


def enc_b(imm, rs2, rs1, f3, op):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | \
           ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 7) << 12) | \
           (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | (op & 0x7F)


def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_j(imm, rd, op):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | \
           ((rd & 0x1F) << 7) | (op & 0x7F)


def hi20(v):
    return ((v + 0x800) >> 12) & 0xFFFFF


def lo12(v):
    return v & 0xFFF


# ---------------------------------------------------------------------------
# 解析一条语句 -> (kind, ...)
# ---------------------------------------------------------------------------
def size_of(mnem, ops, syms):
    """预估指令条数（两遍一致）"""
    m = mnem.lower()
    if m == 'li':
        if len(ops) != 2:
            return 1
        v = ops[1].strip()
        if re.fullmatch(r'[-+]?(0[xX][0-9a-fA-F]+|\d+)', v):
            val = s32(int(v, 0))
            return 1 if -2048 <= val <= 2047 else 2
        return 2
    if m in ('la', 'lla', 'call'):
        return 2
    return 1


def parse_mem_operand(op, ln):
    """解析 'imm(rs1)' 形式"""
    m = re.fullmatch(r'\s*(.*?)\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*', op)
    if not m:
        return None
    return m.group(1), m.group(2)


def assemble_insn(mnem, ops, addr, syms, ln):
    """返回指令字列表（1~2 条）"""
    m = mnem.lower()

    # ---------------- 伪指令 ------------------------------------------------
    if m == 'nop':
        return [enc_i(0, 0, 0, 0, 0x13)]
    if m == 'mv':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(0, rs, 0, rd, 0x13)]
    if m == 'not':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(-1, rs, 4, rd, 0x13)]
    if m == 'neg':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_r(0x20, rs, 0, 0, rd, 0x33)]
    if m == 'seqz':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(1, rs, 3, rd, 0x13)]
    if m == 'snez':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_r(0x00, rs, 0, 3, rd, 0x33)]
    if m == 'sltz':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_r(0x00, 0, rs, 2, rd, 0x33)]
    if m == 'sgtz':
        rd = parse_reg(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_r(0x00, rs, 0, 2, rd, 0x33)]
    if m == 'li':
        rd = parse_reg(ops[0], ln)
        val = s32(eval_expr(ops[1], syms, addr, ln))
        if -2048 <= val <= 2047:
            return [enc_i(val, 0, 0, rd, 0x13)]
        return [enc_u(hi20(val & MASK32), rd, 0x37),
                enc_i(lo12(val), rd, 0, rd, 0x13)]
    if m in ('la', 'lla'):
        rd = parse_reg(ops[0], ln)
        target = eval_expr(ops[1], syms, addr, ln)
        delta = (target - addr) & MASK32
        return [enc_u(hi20(delta), rd, 0x17),
                enc_i(lo12(delta), rd, 0, rd, 0x13)]
    if m == 'call':
        target = eval_expr(ops[0], syms, addr, ln)
        delta = (target - addr) & MASK32
        return [enc_u(hi20(delta), 1, 0x17),
                enc_i(lo12(delta), 1, 0, 1, 0x67)]
    if m == 'j':
        target = eval_expr(ops[0], syms, addr, ln)
        return [enc_j((target - addr) & MASK32, 0, 0x6F)]
    if m == 'jr':
        rs = parse_reg(ops[0], ln)
        return [enc_i(0, rs, 0, 0, 0x67)]
    if m == 'ret':
        return [enc_i(0, 1, 0, 0, 0x67)]
    if m == 'beqz':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, 0, rs, 0, 0x63)]
    if m == 'bnez':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, 0, rs, 1, 0x63)]
    if m == 'blez':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, rs, 0, 5, 0x63)]
    if m == 'bgez':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, 0, rs, 5, 0x63)]
    if m == 'bltz':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, 0, rs, 4, 0x63)]
    if m == 'bgtz':
        rs = parse_reg(ops[0], ln)
        t = eval_expr(ops[1], syms, addr, ln)
        return [enc_b((t - addr) & MASK32, rs, 0, 4, 0x63)]
    if m == 'csrr':
        rd = parse_reg(ops[0], ln); c = parse_csr(ops[1], ln)
        return [enc_i(c, 0, 2, rd, 0x73)]
    if m == 'csrw':
        c = parse_csr(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(c, rs, 1, 0, 0x73)]
    if m == 'csrs':
        c = parse_csr(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(c, rs, 2, 0, 0x73)]
    if m == 'csrc':
        c = parse_csr(ops[0], ln); rs = parse_reg(ops[1], ln)
        return [enc_i(c, rs, 3, 0, 0x73)]
    if m == 'csrwi':
        c = parse_csr(ops[0], ln); z = eval_expr(ops[1], syms, addr, ln) & 0x1F
        return [enc_i(c, z, 5, 0, 0x73)]

    # ---------------- 基础指令 ----------------------------------------------
    if m not in I:
        die("unknown instruction '%s'" % mnem, ln)
    fmt, opcode, f3, f7 = I[m]

    if fmt == 'SYS':
        return [{'ecall': 0x00000073, 'ebreak': 0x00100073,
                 'mret': 0x30200073, 'wfi': 0x10500073}[m]]
    if fmt == 'FENCE':
        return [enc_i(0, 0, f3, 0, 0x0F)]
    if fmt == 'U':
        rd = parse_reg(ops[0], ln)
        v = eval_expr(ops[1], syms, addr, ln)
        if m == 'lui':
            return [enc_u(v, rd, opcode)]
        return [enc_u(v, rd, opcode)]
    if fmt == 'J':
        if len(ops) == 1:
            rd = 1
            tgt = eval_expr(ops[0], syms, addr, ln)
        else:
            rd = parse_reg(ops[0], ln)
            tgt = eval_expr(ops[1], syms, addr, ln)
        return [enc_j((tgt - addr) & MASK32, rd, opcode)]
    if fmt == 'I':        # jalr rd, rs1, imm
        rd = parse_reg(ops[0], ln)
        rs = parse_reg(ops[1], ln)
        imm = eval_expr(ops[2], syms, addr, ln)
        return [enc_i(imm, rs, f3, rd, opcode)]
    if fmt == 'IL':       # load
        rd = parse_reg(ops[0], ln)
        mo = parse_mem_operand(ops[1], ln)
        if mo is None:
            die("bad memory operand", ln)
        off, rsn = mo
        imm = eval_expr(off, syms, addr, ln) if off.strip() else 0
        return [enc_i(imm, parse_reg(rsn, ln), f3, rd, opcode)]
    if fmt == 'II':
        rd = parse_reg(ops[0], ln)
        rs = parse_reg(ops[1], ln)
        imm = eval_expr(ops[2], syms, addr, ln)
        return [enc_i(imm, rs, f3, rd, opcode)]
    if fmt == 'ISH':
        rd = parse_reg(ops[0], ln)
        rs = parse_reg(ops[1], ln)
        sh = eval_expr(ops[2], syms, addr, ln) & 0x1F
        return [enc_i((f7 << 5) | sh, rs, f3, rd, opcode)]
    if fmt == 'S':
        rs2 = parse_reg(ops[0], ln)
        mo = parse_mem_operand(ops[1], ln)
        if mo is None:
            die("bad memory operand", ln)
        off, rsn = mo
        imm = eval_expr(off, syms, addr, ln) if off.strip() else 0
        return [enc_s(imm, rs2, parse_reg(rsn, ln), f3, opcode)]
    if fmt == 'B':
        rs1 = parse_reg(ops[0], ln)
        rs2 = parse_reg(ops[1], ln)
        tgt = eval_expr(ops[2], syms, addr, ln)
        return [enc_b((tgt - addr) & MASK32, rs2, rs1, f3, opcode)]
    if fmt == 'R':
        rd = parse_reg(ops[0], ln)
        rs1 = parse_reg(ops[1], ln)
        rs2 = parse_reg(ops[2], ln)
        return [enc_r(f7, rs2, rs1, f3, rd, opcode)]
    if fmt == 'CSR':
        rd = parse_reg(ops[0], ln)
        c = parse_csr(ops[1], ln)
        if f3 >= 5:      # 立即数形式
            z = eval_expr(ops[2], syms, addr, ln) & 0x1F
            return [enc_i(c, z, f3, rd, 0x73)]
        rs = parse_reg(ops[2], ln)
        return [enc_i(c, rs, f3, rd, 0x73)]

    die("unhandled format for '%s'" % mnem, ln)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('-o', '--outdir', default='.')
    args = ap.parse_args()

    with open(args.src, 'r', encoding='utf-8') as f:
        raw_lines = f.readlines()

    syms = {}
    text = {}          # word_addr -> value
    data = bytearray()
    section = 'text'
    cur_addr = TEXT_BASE
    items = []         # (addr, mnem, ops, ln)
    equ = {}

    # ---------------- pass 1: 布局 -----------------------------------------
    for ln, raw in enumerate(raw_lines, 1):
        line = strip_comment(raw).strip()
        if not line:
            continue
        # 标签
        while True:
            m = re.match(r'^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$', line)
            if not m:
                break
            name = m.group(1)
            if name in syms:
                die("duplicate label '%s'" % name, ln)
            syms[name] = cur_addr
            line = m.group(2).strip()

        if not line:
            continue
        if line.startswith('.'):
            parts = line.split(None, 1)
            d = parts[0].lower()
            rest = parts[1].strip() if len(parts) > 1 else ''
            if d in ('.text', '.section'):
                section = 'text'
                cur_addr = TEXT_BASE + len(text) * 4
                continue
            if d == '.data':
                section = 'data'
                cur_addr = DATA_BASE + len(data)
                continue
            if d in ('.globl', '.global', '.type', '.size', '.option'):
                continue
            if d in ('.equ', '.set'):
                parts2 = rest.replace(',', ' ').split()
                if len(parts2) < 2:
                    die("bad .equ", ln)
                equ[parts2[0]] = eval_expr(parts2[1], {**syms, **equ}, cur_addr, ln)
                syms[parts2[0]] = equ[parts2[0]]
                continue
            if d == '.align':
                n = eval_expr(rest, {**syms, **equ}, cur_addr, ln)
                align = 1 << n
                if section == 'text':
                    while (cur_addr % align) != 0:
                        text[cur_addr // 4] = 0x00000013
                        cur_addr += 4
                else:
                    while (len(data) % align) != 0:
                        data.append(0)
                    cur_addr = DATA_BASE + len(data)
                continue
            if d == '.word' and section == 'text':
                for tok in [t.strip() for t in rest.split(',') if t.strip()]:
                    v = eval_expr(tok, {**syms, **equ}, cur_addr, ln)
                    text[cur_addr // 4] = v & MASK32
                    cur_addr += 4
                continue
            if d in ('.word', '.half', '.byte', '.space', '.string', '.asciz', '.ascii'):
                for tok in [t.strip() for t in rest.split(',') if t.strip()]:
                    if d == '.word':
                        v = eval_expr(tok, {**syms, **equ}, cur_addr, ln)
                        data.extend(int(v & MASK32).to_bytes(4, 'little'))
                        cur_addr += 4
                    elif d == '.half':
                        v = eval_expr(tok, {**syms, **equ}, cur_addr, ln)
                        data.extend(int(v & 0xFFFF).to_bytes(2, 'little'))
                        cur_addr += 2
                    elif d == '.byte':
                        v = eval_expr(tok, {**syms, **equ}, cur_addr, ln)
                        data.append(v & 0xFF)
                        cur_addr += 1
                    elif d == '.space':
                        n = eval_expr(tok, {**syms, **equ}, cur_addr, ln)
                        data.extend(b'\x00' * n)
                        cur_addr += n
                    else:
                        s = tok.strip('"')
                        data.extend(s.encode('latin-1'))
                        cur_addr += len(s)
                        if d in ('.string', '.asciz'):
                            data.append(0)
                            cur_addr += 1
                continue
            if d == '.org':
                die(".org not supported", ln)
            die("unknown directive '%s'" % d, ln)

        # 指令
        parts = line.split(None, 1)
        mnem = parts[0]
        opstr = parts[1] if len(parts) > 1 else ''
        ops = [o.strip() for o in opstr.split(',')] if opstr.strip() else []
        n = size_of(mnem, ops, syms)
        items.append((cur_addr, mnem, ops, ln, n))
        cur_addr += 4 * n

    text_end = cur_addr if section == 'text' else 0
    # 注意: 若最后停在 data 段, text_end 用文本最大地址重算
    tmax = 0
    for (a, _, _, _, n) in items:
        tmax = max(tmax, a + 4 * n)

    # ---------------- pass 2: 编码 -----------------------------------------
    listing = []
    for (a, mnem, ops, ln, n) in items:
        words = assemble_insn(mnem, ops, a, {**syms, **equ}, ln)
        if len(words) > n:
            die("instruction expands beyond reserved size", ln)
        while len(words) < n:
            words.append(0x00000013)     # nop padding
        for i, w in enumerate(words):
            text[(a // 4) + i] = w & MASK32
        listing.append((a, mnem, ', '.join(ops), words))

    # ---------------- 输出 --------------------------------------------------
    os.makedirs(args.outdir, exist_ok=True)

    def write_hex128(path, words):
        """每行 4 个字（128 位），高位字在前，供 128 位宽存储器直接 $readmemh"""
        n = ((len(words) + 3) // 4) * 4
        if n == 0:
            n = 4
        ws = list(words) + [0] * (n - len(words))
        with open(path, 'w', encoding='ascii') as f:
            for i in range(0, n, 4):
                f.write('%08x%08x%08x%08x\n' % (ws[i + 3], ws[i + 2], ws[i + 1], ws[i]))

    nwords = (max(tmax, 4) + 3) // 4 if tmax > 0 else 1
    imem_words = [text.get(i, 0x00000000) for i in range(nwords)]
    write_hex128(os.path.join(args.outdir, 'imem.hex'), imem_words)

    data_words = (len(data) + 3) // 4
    if data_words == 0:
        data_words = 1
    dwords = [int.from_bytes(data[i * 4:i * 4 + 4].ljust(4, b'\x00'), 'little')
              for i in range(data_words)]
    write_hex128(os.path.join(args.outdir, 'dmem.hex'), dwords)

    with open(os.path.join(args.outdir, 'map.txt'), 'w', encoding='utf-8') as f:
        f.write('# symbols\n')
        for k, v in sorted(syms.items(), key=lambda kv: kv[1]):
            f.write('%-24s %08x\n' % (k, v))
        f.write('\n# listing\n')
        for (a, mnem, ops, words) in listing:
            f.write('%08x  %08x  %-8s %s\n' % (a, words[0], mnem, ops))

    print("assembled %s -> %s (text %d words, data %d bytes)"
          % (args.src, args.outdir, nwords, len(data)))


if __name__ == '__main__':
    try:
        main()
    except AsmError as e:
        print("error: %s" % e, file=sys.stderr)
        sys.exit(1)
