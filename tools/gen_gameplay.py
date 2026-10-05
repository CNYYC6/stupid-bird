#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 玩法素材生成器（路障 / 金币）

路障做成「可竖向平铺的柱体 + 端头盖」：
  * obs_pillar.png  64x40 逻辑像素，纵向无缝，任意高度靠 texture_repeat + region 拼；
  * obs_cap_top.png   地面柱的顶部端头（带橙白警示斜纹）；
  * obs_cap_hang.png  悬挂柱的底部端头。
这样一根柱子无论多高都只用一个 Sprite2D，不需要堆节点，也不会出现非整数缩放的像素抖动。
"""
from __future__ import annotations

import os
import numpy as np

from gen_ui import S, ART, rgba, save, dilate

# ------------------------------------------------------------------ 调色板
C_DARK = "#343A42"
C_JOINT = "#5A6068"
C_LIT = "#AEB3BB"
C_MID = "#8B9099"
C_SH = "#6A707A"
O_DARK = "#B85F22"
O_MID = "#E8843C"
O_LIT = "#F5A860"
WARN_W = "#F2F2F0"

PILLAR_W, PILLAR_H = 64, 200   # 200 逻辑像素 = 1200 屏幕像素，比任何单根柱子都高，不用依赖 region 重复采样
CAP_H = 14
# 金币的逻辑直径。放大 6 倍后是 84 屏幕像素，大约是小鸟可视宽度的 6 成 ——
# 原来 24（144 屏幕像素）几乎和小鸟一样大，挡视线又显得廉价。
COIN = 14


def band(w: int) -> np.ndarray:
    """柱体某一行的横向明暗：左受光、右背光，两端深色描边。"""
    row = np.zeros((w, 4), dtype=np.float32)
    for x in range(w):
        if x < 3 or x >= w - 3:
            c = rgba(C_DARK)
        elif x < 10:
            c = rgba(C_LIT)
        elif x < int(w * 0.72):
            c = rgba(C_MID)
        else:
            c = rgba(C_SH)
        row[x] = c
    return row


def make_pillar(w: int = PILLAR_W, h: int = PILLAR_H, seed: int = 7) -> np.ndarray:
    """纵向可平铺的混凝土柱体：每 40 像素一道砌缝。"""
    img = np.zeros((h, w, 4), dtype=np.float32)
    img[:] = band(w)[None, :, :]

    # 砌缝：顶部一条深色 + 一条高光，平铺后每 40 像素重复一次
    img[0:3, :] = rgba(C_JOINT)
    img[3, :] = rgba(C_LIT)

    rng = np.random.default_rng(seed)
    for _ in range(w * h // 22):                      # 混凝土麻点
        x = int(rng.integers(3, w - 3))
        y = int(rng.integers(4, h))
        img[y, x, :3] *= 1.0 + (rng.random() - 0.5) * 0.22
    np.clip(img, 0, 255, out=img)
    img[:, :, 3] = 255.0
    return img


def make_cap(w: int = PILLAR_W, h: int = CAP_H, flip: bool = False) -> np.ndarray:
    """柱体端头：橙白警示斜纹 + 顶部/底部圆角。"""
    img = np.zeros((h, w, 4), dtype=np.float32)
    img[:] = band(w)[None, :, :]
    base = band(w)

    for y in range(h):
        for x in range(w):
            c = base[x].copy()
            if 3 <= y <= h - 4:
                # 45 度警示斜纹
                c[:3] = rgba(O_LIT if (x + y) % 12 < 6 else WARN_W)[:3]
            img[y, x] = c

    # 两条横向压边，把警示带框住
    img[2, :] = rgba(O_DARK)
    img[h - 3, :] = rgba(O_DARK)
    img[:, :3] = rgba(C_DARK)
    img[:, -3:] = rgba(C_DARK)

    # 端头圆角
    if flip:
        img[h - 1, :] = 0
        img[h - 1, 3:w - 3] = rgba(C_DARK)
        img[h - 2, :3] = 0
        img[h - 2, -3:] = 0
    else:
        img[0, :] = 0
        img[0, 3:w - 3] = rgba(C_DARK)
        img[1, :3] = 0
        img[1, -3:] = 0
    return img


def make_coin(index: int, size: int = COIN) -> np.ndarray:
    """金币旋转动画的 4 帧：用椭圆宽度模拟翻转。

    几何全部按 size/24 缩放，所以改 COIN 一个常数就能整组放大缩小，
    不用再去手调每一帧的椭圆半径（描边粗细、高光位置会跟着一起缩）。
    """
    s = size / 24.0
    widths = ((24 - 2) * s, 17 * s, 8 * s, 17 * s)
    cw = widths[index % 4]
    img = np.zeros((size, size, 4), dtype=np.float32)
    yy, xx = np.mgrid[0:size, 0:size]
    cx = cy = (size - 1) / 2.0
    rx, ry = cw / 2.0, 11.0 * s
    d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2

    outline = (d > 1.0) & (d <= 1.45)
    img[outline] = rgba("#4A3418")
    img[(d <= 1.0) & (d > 0.66)] = rgba("#D9A62E")
    img[d <= 0.66] = rgba("#FBF236")
    # 左上高光
    hi = (((xx - cx + rx * 0.32) / max(rx * 0.42, 0.6)) ** 2
          + ((yy - cy + ry * 0.3) / (4.0 * s)) ** 2) <= 1.0
    img[hi & (d <= 0.66)] = rgba("#FFF6CE")
    img[:, :, 3] = np.where(outline | (d <= 1.0), 255.0, 0.0)
    return img


def main() -> None:
    print("生成玩法素材：")
    save(make_pillar(), "obs_pillar.png")
    save(make_cap(), "obs_cap_top.png")
    save(make_cap(flip=True), "obs_cap_hang.png")
    for i in range(4):
        save(make_coin(i), f"coin_{i}.png")


if __name__ == "__main__":
    main()
