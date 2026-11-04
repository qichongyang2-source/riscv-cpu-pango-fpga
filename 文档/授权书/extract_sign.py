# -*- coding: utf-8 -*-
"""extract_sign.py : 从白纸照片中抠出每段手写内容

做法：先用低频背景估计把纸面拉成纯白（白平衡），再按暗度裁掉四周空白，
输出不透明 RGB——贴到白底页面上时纸底与页面融为一体，只留下墨迹。
"""
import os
import shutil

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sign_src.jpg')
OUT = os.path.join(HERE, 'crops')
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT, exist_ok=True)

im = Image.open(SRC).rotate(90, expand=True).convert('RGB')
w, h = im.size
im = im.crop((60, 20, w - 60, h - 40))
g = np.array(im.convert('L')).astype(np.float32)
print('cropped size', im.size)

ink = g < 110
rows = ink.sum(axis=1)

bands = []
in_band, start = False, 0
for y, v in enumerate(rows):
    if v > 3 and not in_band:
        in_band, start = True, y
    elif v <= 3 and in_band:
        in_band = False
        bands.append([start, y])
if in_band:
    bands.append([start, len(rows)])

merged = []
for b in bands:
    if merged and b[0] - merged[-1][1] < 45:
        merged[-1][1] = b[1]
    else:
        merged.append(b)

bands = []
for y0, y1 in merged:
    while y1 > y0 + 20 and ink[y1 - 1, :].sum() > 0.25 * ink.shape[1]:
        y1 -= 1
    if y1 - y0 > 20:
        bands.append((y0, y1))

print('bands:', bands)
names = ['team_id', 'member', 'year', 'signature', 'date']

for i, (y0, y1) in enumerate(bands):
    # 内容都靠左，固定 x 范围即可避开右侧噪点与桌面
    x0, x1 = 40, 900
    pad = 8
    y0p, y1p = max(0, y0 - pad), min(g.shape[0], y1 + pad)

    sub = im.crop((x0, y0p, x1, y1p))
    rgb = np.array(sub).astype(np.float32)

    # 低频背景（纸面亮度）估计：缩小 -> 取亮 -> 放大
    small_w = max(2, sub.size[0] // 24)
    small_h = max(2, sub.size[1] // 8)
    small = sub.convert('L').resize((small_w, small_h), Image.BOX)
    small = small.filter(ImageFilter.MaxFilter(3))
    bg = np.array(small.resize(sub.size, Image.BILINEAR)).astype(np.float32)
    bg = np.maximum(bg, 60.0)

    # 白平衡：纸面拉到 246，墨迹保持深色
    scale = 246.0 / bg
    norm = np.clip(rgb * scale[..., None], 0, 255)
    lum = np.array(Image.fromarray(norm.astype(np.uint8), 'RGB').convert('L')).astype(np.float32)

    # 用暗度裁掉四周空白
    mask = lum < 205
    ys, xs = np.where(mask)
    if len(ys) == 0:
        continue
    yy0, yy1 = max(0, ys.min() - 4), min(lum.shape[0], ys.max() + 5)
    xx0, xx1 = max(0, xs.min() - 4), min(lum.shape[1], xs.max() + 5)

    out = Image.fromarray(norm[yy0:yy1, xx0:xx1].astype(np.uint8), 'RGB')
    name = names[i] if i < len(names) else 'extra%d' % i
    path = os.path.join(OUT, '%d_%s.png' % (i, name))
    out.save(path)
    print('%-10s w=%4d h=%3d  %s' % (name, out.size[0], out.size[1], path))
