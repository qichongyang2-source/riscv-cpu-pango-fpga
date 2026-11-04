#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
train_mnist.py : 训练 196-16-10 小 MLP，量化为 INT8，导出给 AI 加速器的头文件

  - 输入：28x28 下采样到 14x14，量化到 0..127
  - 权重：per-tensor 对称量化（-127..127）
  - 偏置：折算成加速器 int32 累加域的整数
  - 逐层激活量化：h8 = clip(y1_int >> SHIFT)
  - 导出 sw/ai/mnist_data.h（权重 + 若干测试图）
"""

import gzip
import os
import struct
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
OUT_H = os.path.join(HERE, 'mnist_data.h')

IMG_SIZE = 28
DS = 14
IN = DS * DS        # 196
HID = 32
OUT = 10
SHIFT = 15

MNIST_URLS = {
    'train-images-idx3-ubyte.gz': 'https://storage.googleapis.com/cvdf-datasets/mnist/train-images-idx3-ubyte.gz',
    'train-labels-idx1-ubyte.gz': 'https://storage.googleapis.com/cvdf-datasets/mnist/train-labels-idx1-ubyte.gz',
    't10k-images-idx3-ubyte.gz':  'https://storage.googleapis.com/cvdf-datasets/mnist/t10k-images-idx3-ubyte.gz',
    't10k-labels-idx1-ubyte.gz':  'https://storage.googleapis.com/cvdf-datasets/mnist/t10k-labels-idx1-ubyte.gz',
}


def ensure_data():
    """数据缺失时从官方镜像下载（约 11 MB）"""
    os.makedirs(DATA, exist_ok=True)
    for fn, url in MNIST_URLS.items():
        dst = os.path.join(DATA, fn)
        if not os.path.exists(dst):
            print('downloading %s ...' % fn)
            urllib.request.urlretrieve(url, dst)


def load_idx_images(path):
    with gzip.open(path, 'rb') as f:
        magic, n, rows, cols = struct.unpack('>IIII', f.read(16))
        assert magic == 2051
        buf = f.read(n * rows * cols)
        return np.frombuffer(buf, dtype=np.uint8).reshape(n, rows, cols)


def load_idx_labels(path):
    with gzip.open(path, 'rb') as f:
        magic, n = struct.unpack('>II', f.read(8))
        assert magic == 2049
        return np.frombuffer(f.read(n), dtype=np.uint8)


def downsample(imgs):
    x = imgs.astype(np.float32).reshape(-1, DS, 2, DS, 2).mean(axis=(2, 4))
    return (x / 255.0).reshape(-1, DS * DS)


def quant_x(xf):
    return np.clip(np.round(xf * 127.0), 0, 127).astype(np.int32)


def train(x, y, epochs=18, lr=1e-3):
    rng = np.random.default_rng(0)
    w1 = rng.normal(0, np.sqrt(2.0 / IN), (IN, HID)).astype(np.float32)
    b1 = np.zeros(HID, np.float32)
    w2 = rng.normal(0, np.sqrt(2.0 / HID), (HID, OUT)).astype(np.float32)
    b2 = np.zeros(OUT, np.float32)

    params = [w1, b1, w2, b2]
    m = [np.zeros_like(p) for p in params]
    v = [np.zeros_like(p) for p in params]
    beta1, beta2, eps = 0.9, 0.999, 1e-8
    step = 0
    n = x.shape[0]
    for ep in range(epochs):
        perm = rng.permutation(n)
        tot = 0.0
        for i in range(0, n, 128):
            idx = perm[i:i + 128]
            xb, yb = x[idx], y[idx]
            h = np.maximum(0, xb @ w1 + b1)
            z = h @ w2 + b2
            z -= z.max(axis=1, keepdims=True)
            p = np.exp(z)
            p /= p.sum(axis=1, keepdims=True)
            loss = -np.log(p[np.arange(len(idx)), yb] + 1e-9).mean()
            tot += loss * len(idx)

            dz = p.copy()
            dz[np.arange(len(idx)), yb] -= 1.0
            dz /= len(idx)
            dw2 = h.T @ dz
            db2 = dz.sum(axis=0)
            dh = dz @ w2.T
            dh[h <= 0] = 0
            dw1 = xb.T @ dh
            db1 = dh.sum(axis=0)

            grads = [dw1, db1, dw2, db2]
            step += 1
            for j, (p_, g_) in enumerate(zip(params, grads)):
                m[j] = beta1 * m[j] + (1 - beta1) * g_
                v[j] = beta2 * v[j] + (1 - beta2) * (g_ * g_)
                mh = m[j] / (1 - beta1 ** step)
                vh = v[j] / (1 - beta2 ** step)
                p_ -= lr * mh / (np.sqrt(vh) + eps)

        print('epoch %2d  loss %.4f' % (ep + 1, tot / n))
    return w1, b1, w2, b2


def quant_weights(w1, b1, w2, b2, xcal):
    """per-tensor 权重量化 + 按校准集确定激活缩放 M"""
    s1 = np.abs(w1).max() / 127.0
    s2 = np.abs(w2).max() / 127.0
    w1q = np.clip(np.round(w1 / s1), -127, 127).astype(np.int32)
    w2q = np.clip(np.round(w2 / s2), -127, 127).astype(np.int32)
    k1 = 127.0 / s1                      # y1_int = k1 * y1_float
    b1q = np.round(b1 * k1).astype(np.int32)

    y1c = np.maximum(0, xcal @ w1q + b1q)
    mx = max(1, int(y1c.max()))          # 校准出的最大正激活
    M = int((127.0 * (2 ** SHIFT)) / mx)  # h8 = (y1 * M) >> SHIFT
    mx_f = mx / k1                        # 对应的浮点激活上限

    c2 = 127.0 / (s2 * mx_f)
    b2q = np.round(b2 * c2).astype(np.int32)
    return w1q, b1q, w2q, b2q, M, mx


def sim_int8(x8, w1q, b1q, w2q, b2q, M):
    y1 = x8 @ w1q + b1q
    h8 = np.clip((np.maximum(y1, 0) * M) >> SHIFT, 0, 127)
    y2 = h8 @ w2q + b2q
    return y1, h8, y2


def main():
    ensure_data()
    xtr = downsample(load_idx_images(os.path.join(DATA, 'train-images-idx3-ubyte.gz')))
    ytr = load_idx_labels(os.path.join(DATA, 'train-labels-idx1-ubyte.gz'))
    xte = downsample(load_idx_images(os.path.join(DATA, 't10k-images-idx3-ubyte.gz')))
    yte = load_idx_labels(os.path.join(DATA, 't10k-labels-idx1-ubyte.gz'))

    if os.path.exists(os.path.join(HERE, 'w1.npy')):
        w1 = np.load(os.path.join(HERE, 'w1.npy'))
        b1 = np.load(os.path.join(HERE, 'b1.npy'))
        w2 = np.load(os.path.join(HERE, 'w2.npy'))
        b2 = np.load(os.path.join(HERE, 'b2.npy'))
        print('loaded cached weights')
    else:
        w1, b1, w2, b2 = train(xtr, ytr)
        np.save(os.path.join(HERE, 'w1.npy'), w1)
        np.save(os.path.join(HERE, 'b1.npy'), b1)
        np.save(os.path.join(HERE, 'w2.npy'), w2)
        np.save(os.path.join(HERE, 'b2.npy'), b2)

    z = np.maximum(0, xte @ w1 + b1) @ w2 + b2
    acc_f = (z.argmax(axis=1) == yte).mean()
    print('float accuracy: %.4f' % acc_f)

    xcal = quant_x(xtr[:2000])
    w1q, b1q, w2q, b2q, M, mx = quant_weights(w1, b1, w2, b2, xcal)
    print('calib max activation = %d, M = %d (shift %d)' % (mx, M, SHIFT))

    x8 = quant_x(xte[:2000])
    _, _, y2 = sim_int8(x8, w1q, b1q, w2q, b2q, M)
    print('int8 accuracy(2k): %.4f' % (y2.argmax(axis=1) == yte[:2000]).mean())

    x8_all = quant_x(xte)
    _, _, y2 = sim_int8(x8_all, w1q, b1q, w2q, b2q, M)
    acc = (y2.argmax(axis=1) == yte).mean()
    print('full int8 accuracy: %.4f' % acc)

    export(w1q, b1q, w2q, b2q, M, x8_all, yte)
    return 0


def export(w1q, b1q, w2q, b2q, M, x8, yte):
    """导出头文件：权重按加速器布局（每 4 个输出一组，K 行 x 4 列）"""
    nimg = 20
    # w1: (IN, HID) -> 每组 (IN x 4)，行优先
    groups1 = []
    for g in range(0, HID, 4):
        blk = w1q[:, g:g + 4]
        groups1.append(blk.reshape(-1))
    w1_bytes = np.concatenate(groups1)
    # w2: (HID, OUT) -> 3 组，最后补零到 4 列
    groups2 = []
    for g in range(0, 12, 4):
        blk = np.zeros((HID, 4), np.int32)
        cols = min(4, OUT - g)
        if cols > 0:
            blk[:, :cols] = w2q[:, g:g + cols]
        groups2.append(blk.reshape(-1))
    w2_bytes = np.concatenate(groups2)

    def arr_i8(name, a):
        a = a.astype(np.int8)
        vals = ', '.join(str(int(v)) for v in a)
        return 'static const signed char %s[%d] = {%s};\n' % (name, len(a), vals)

    def arr_i32(name, a):
        vals = ', '.join(str(int(v)) for v in a)
        return 'static const int %s[%d] = {%s};\n' % (name, len(a), vals)

    lines = []
    lines.append('/* auto-generated by train_mnist.py, do not edit */\n')
    lines.append('#ifndef MNIST_DATA_H\n#define MNIST_DATA_H\n\n')
    lines.append('#define MNIST_IN    %d\n' % IN)
    lines.append('#define MNIST_HID   %d\n' % HID)
    lines.append('#define MNIST_OUT   %d\n' % OUT)
    lines.append('#define MNIST_M     %d\n' % M)
    lines.append('#define MNIST_SHIFT %d\n' % SHIFT)
    lines.append('#define MNIST_IMGS  %d\n\n' % nimg)
    lines.append(arr_i8('mnist_w1', w1_bytes))
    lines.append(arr_i8('mnist_w2', w2_bytes))
    lines.append(arr_i32('mnist_b1', b1q))
    lines.append(arr_i32('mnist_b2', b2q))
    lines.append('\nstatic const signed char mnist_x[%d][%d] = {\n' % (nimg, IN))
    for i in range(nimg):
        row = ', '.join(str(int(v)) for v in x8[i].astype(np.int8))
        lines.append('  {%s},\n' % row)
    lines.append('};\n')
    lines.append('static const unsigned char mnist_label[%d] = {%s};\n'
                 % (nimg, ', '.join(str(int(v)) for v in yte[:nimg])))
    lines.append('\n#endif\n')

    with open(OUT_H, 'w', encoding='ascii') as f:
        f.writelines(lines)
    print('wrote %s (w1=%d B, w2=%d B, %d imgs)' % (OUT_H, len(w1_bytes), len(w2_bytes), nimg))


if __name__ == '__main__':
    sys.exit(main())
