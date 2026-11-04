# -*- coding: utf-8 -*-
"""make_figs.py : 生成报告用的架构图（PNG）"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '图')
os.makedirs(OUT, exist_ok=True)

FONT = 'C:/Windows/Fonts/msyh.ttc'
FONT_B = 'C:/Windows/Fonts/msyhbd.ttc'


def f(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def box(d, x, y, w, h, text, fill='#EAF2FB', outline='#2F5597', fs=22, bold=False):
    d.rounded_rectangle([x, y, x + w, y + h], radius=10, fill=fill, outline=outline, width=3)
    lines = text.split('\n')
    fnt = f(fs, bold)
    th = sum(d.textbbox((0, 0), ln, font=fnt)[3] for ln in lines) + 6 * (len(lines) - 1)
    cy = y + (h - th) // 2
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=fnt)
        d.text((x + (w - (bb[2] - bb[0])) // 2, cy), ln, font=fnt, fill='#1F2A44')
        cy += (bb[3] - bb[1]) + 6


def arrow(d, x1, y1, x2, y2, color='#2F5597', width=3):
    d.line([x1, y1, x2, y2], fill=color, width=width)
    import math
    ang = math.atan2(y2 - y1, x2 - x1)
    L = 14
    for s in (0.5, -0.5):
        d.line([x2, y2, x2 - L * math.cos(ang - s), y2 - L * math.sin(ang - s)], fill=color, width=width)


def fig_pipeline():
    W, H = 1500, 560
    img = Image.new('RGB', (W, H), 'white')
    d = ImageDraw.Draw(img)

    stages = [('IF\n取指', 60), ('ID\n译码/读寄存器', 330), ('EX\n执行/分支', 640),
              ('MEM\n访存', 950), ('WB\n写回', 1230)]
    for name, x in stages:
        box(d, x, 110, 210, 110, name, fs=24, bold=True)
    for i in range(4):
        arrow(d, stages[i][1] + 210, 165, stages[i + 1][1] - 8, 165)

    box(d, 60, 300, 300, 90, '指令 Cache\n2 KB / 2 路 / 整行突发', fill='#FDF2E9', outline='#C55A11', fs=20)
    arrow(d, 165, 300, 165, 226)
    box(d, 420, 300, 300, 90, '数据 Cache\n2 KB / 2 路 / 写穿', fill='#FDF2E9', outline='#C55A11', fs=20)
    arrow(d, 1040, 300, 1040, 226)

    box(d, 780, 300, 280, 90, 'BTB + 2 位计数器\n64 项，预测跳转', fill='#E2EFDA', outline='#548235', fs=20)
    arrow(d, 780, 345, 745, 190)

    box(d, 60, 450, 420, 100, '冒险单元：全转发 / load-use 停顿\nWB→ID 旁路 / CSR 写后读互锁', fill='#FBE5D6', outline='#C55A11', fs=20)
    box(d, 520, 450, 380, 100, 'CSR + 异常/中断\nmtvec 向量、MEIP/MTIP、mret', fill='#EDE7F6', outline='#5B3F9E', fs=20)
    box(d, 940, 450, 420, 100, 'M 扩展\nMUL 在 MEM 级；DIV 32 拍迭代', fill='#E2EFDA', outline='#548235', fs=20)

    img.save(os.path.join(OUT, 'fig1_pipeline.png'))
    print('fig1 ok')


def fig_soc():
    W, H = 1500, 800
    img = Image.new('RGB', (W, H), 'white')
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([40, 80, 1460, 820], radius=16, outline='#7F7F7F', width=3)
    d.text((60, 92), 'soc_top', font=f(20, True), fill='#595959')

    box(d, 600, 130, 300, 110, 'RISC-V 内核\n5 级流水 + BTB', fs=24, bold=True)

    box(d, 160, 320, 300, 100, 'I-Cache\n2 KB / 2 路', fill='#FDF2E9', outline='#C55A11', fs=21)
    box(d, 600, 320, 300, 100, 'D-Cache\n2 KB / 2 路 / 写穿', fill='#FDF2E9', outline='#C55A11', fs=21)
    arrow(d, 620, 240, 400, 318)
    arrow(d, 880, 240, 800, 318)

    box(d, 100, 500, 360, 100, 'IMEM  64 KB\n4096 x 128 位 (BRAM)', fill='#EDE7F6', outline='#5B3F9E', fs=20)
    box(d, 560, 500, 360, 100, 'DMEM  64 KB\n4096 x 128 位 (BRAM)', fill='#EDE7F6', outline='#5B3F9E', fs=20)
    arrow(d, 310, 420, 280, 498)
    arrow(d, 750, 420, 740, 498)

    box(d, 1040, 300, 360, 170, 'AI 加速器\nINT8 FC / RELU / ARGMAX\n8 KB 本地缓冲', fill='#E2EFDA', outline='#548235', fs=21)
    arrow(d, 900, 200, 1100, 298)
    d.text((905, 232), 'MMIO', font=f(18), fill='#548235')

    box(d, 1040, 520, 170, 90, 'UART\n8N1', fill='#E7E6E6', outline='#7F7F7F', fs=19)
    box(d, 1230, 520, 170, 90, 'GPIO', fill='#E7E6E6', outline='#7F7F7F', fs=19)
    box(d, 1040, 640, 170, 90, 'TIMER\n64 位', fill='#E7E6E6', outline='#7F7F7F', fs=19)
    box(d, 1230, 640, 170, 90, '测试/中断\n寄存器', fill='#E7E6E6', outline='#7F7F7F', fs=17)
    arrow(d, 900, 250, 1040, 550)

    d.text((60, 745), '地址空间：0x0000_0000 IMEM｜0x1000_0000 DMEM｜0x2000_0000 UART｜'
                      '0x2000_1000 GPIO｜0x2000_2000 TIMER',
           font=f(16), fill='#404040')
    d.text((60, 772), '0x2000_4000 AI 寄存器｜0x2000_8000 AI 缓冲（8 KB）｜'
                      '0x3000_0000 仿真测试退出',
           font=f(16), fill='#404040')

    img.save(os.path.join(OUT, 'fig2_soc.png'))
    print('fig2 ok')


if __name__ == '__main__':
    fig_pipeline()
    fig_soc()
