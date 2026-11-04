# -*- coding: utf-8 -*-
"""compose_auth.py : 把手写内容合成到参赛承诺书 PDF 上

输入：sign_src.jpg（白纸签名照）、page/page-0001.png（300 dpi 渲染页）
输出：授权书_已签名.pdf
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sign_src.jpg')
PAGE = os.path.join(HERE, 'page', 'page-0001.png')
OUT_PNG = os.path.join(HERE, 'auth_signed.png')
OUT_PDF = os.path.join(HERE, '参赛作品承诺及使用授权书_已签名.pdf')

# 手写内容在原图中的裁切框（旋转后坐标）
RECTS = {
    'team_id':   (800, 95, 1100, 225),
    'member':    (812, 312, 1030, 448),
    'year':      (795, 572, 995, 668),
    'signature': (808, 752, 1032, 868),
    'date':      (783, 908, 1220, 1006),
}

# 在页面上的位置：左上角 (x, y) 与目标高度（像素，300 dpi）
PLACE = {
    'team_id':   (800, 528, 56),
    'member':    (1395, 524, 60),
    'year':      (815, 660, 52),
    'signature': (1602, 2472, 74),
    'date':      (1012, 2998, 58),
}


def extract(rect):
    """裁出字迹并白平衡，返回 RGB 图"""
    x0, y0, x1, y1 = rect
    crop = rot.crop((x0, y0, x1, y1)).convert('RGB')
    rgb = np.array(crop).astype(np.float32)
    lum = np.array(crop.convert('L')).astype(np.float32)

    # 纸面亮度：取较亮的 75 分位，避免被墨迹拉低
    paper = float(np.percentile(lum, 75))
    paper = max(paper, 120.0)
    scale = min(250.0 / paper, 2.2)
    norm = np.clip(rgb * scale, 0, 255)

    nl = np.array(Image.fromarray(norm.astype(np.uint8)).convert('L')).astype(np.float32)
    ys, xs = np.where(nl < 200)
    if len(ys) == 0:
        return None
    pad = 3
    yy0, yy1 = max(0, ys.min() - pad), min(nl.shape[0], ys.max() + pad + 1)
    xx0, xx1 = max(0, xs.min() - pad), min(nl.shape[1], xs.max() + pad + 1)
    return Image.fromarray(norm[yy0:yy1, xx0:xx1].astype(np.uint8), 'RGB')


def main():
    global rot
    rot = Image.open(SRC).rotate(90, expand=True).convert('RGB')

    page = np.array(Image.open(PAGE).convert('RGB')).astype(np.float32)
    H, W = page.shape[:2]
    print('page', W, H)

    for key, rect in RECTS.items():
        img = extract(rect)
        if img is None:
            print('skip', key)
            continue
        x, y, th = PLACE[key]
        tw = max(1, int(round(img.width * th / float(img.height))))
        img = img.resize((tw, th), Image.LANCZOS)

        arr = np.array(img).astype(np.float32)
        # 纸底压成纯白，避免出现灰色方块
        arr[arr >= 238] = 255.0
        # 只压暗：纸底（≥245）保持页面原样，墨迹按比例变暗
        f = np.clip(arr / 245.0, 0.0, 1.0) ** 2.0

        y0, x0 = y, x
        y1, x1 = min(H, y0 + th), min(W, x0 + tw)
        fy, fx = y1 - y0, x1 - x0
        if fy <= 0 or fx <= 0:
            print('out of page', key)
            continue
        page[y0:y1, x0:x1] *= f[:fy, :fx]
        print('%-10s -> (%d,%d) %dx%d' % (key, x, y, fx, fy))

    out = np.clip(page, 0, 255).astype(np.uint8)
    Image.fromarray(out).save(OUT_PNG)
    Image.fromarray(out).save(OUT_PDF, 'PDF', resolution=300.0)
    print('saved', OUT_PDF, '%.1f KB' % (os.path.getsize(OUT_PDF) / 1024.0))


if __name__ == '__main__':
    main()
