#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 随机事件素材生成器

产出三类东西：
  * ev_portal_0..3.png   传送门的 4 帧漩涡（代码里轮播，不建 SpriteFrames）
  * ev_meteor.png        陨石（带火焰拖尾）
  * ev_title_*.png / ev_sub_*.png   事件横幅（中文只能烘成贴图）
"""
from __future__ import annotations

import os
import numpy as np

from gen_backgrounds import S, rgb, blank, ellipse_wrap, disc_wrap, upscale, save, ART
from gen_ui import make_label

PORTAL_W, PORTAL_H = 36, 60
METEOR = 18


def make_portal_frame(i: int) -> np.ndarray:
    """传送门：一个立着的椭圆环，内部是旋转的星云漩涡。"""
    w, h = PORTAL_W, PORTAL_H
    img = blank(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    rx, ry = w * 0.48, h * 0.48

    # 归一化的椭圆坐标（>1 在外面）
    nx = (xx - cx) / rx
    ny = (yy - cy) / ry
    r = np.sqrt(nx * nx + ny * ny)
    ang = np.arctan2(ny, nx)

    # 外环
    ring = (r > 0.80) & (r <= 1.0)
    img[:, :, :3][ring] = rgb("#2A1050")
    img[:, :, 3][ring] = 255.0
    ring2 = (r > 0.84) & (r <= 0.95)
    img[:, :, :3][ring2] = rgb(["#8A4AFF", "#C9A8FF", "#5AE0FF", "#FF7AE0"][i % 4])
    img[:, :, 3][ring2] = 255.0

    # 内部漩涡：随帧号旋转的螺旋条纹
    inner = r <= 0.80
    spiral = np.sin(ang * 3.0 + r * 9.0 - i * (np.pi / 2.0))
    deep = inner & (spiral > 0.25)
    mid = inner & (spiral <= 0.25) & (spiral > -0.35)
    img[:, :, :3][inner] = rgb("#1A0A38")
    img[:, :, 3][inner] = 255.0
    img[:, :, :3][mid] = rgb("#4A1E8A")
    img[:, :, :3][deep] = rgb("#9A5AFF")
    # 核心亮点
    core = r <= 0.26
    img[:, :, :3][core] = rgb("#E8D8FF")
    # 高光边
    img[:, :, :3][(r > 0.74) & (r <= 0.80)] = rgb("#FFF0FF")
    return img


def make_meteor() -> np.ndarray:
    """陨石：深色石块 + 左上受光 + 右上方向的火焰拖尾。"""
    w = h = METEOR
    img = blank(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = 8.5, 10.5
    body = disc_wrap(w, h, cx, cy, 6.2)
    img[:, :, :3][body] = rgb("#4A3A32")
    img[:, :, 3][body] = 255.0
    rng = np.random.default_rng(3)
    for _ in range(26):
        a = rng.uniform(0, np.pi * 2)
        rr = rng.uniform(0, 5.6)
        x = int(cx + np.cos(a) * rr) % w
        y = int(cy + np.sin(a) * rr)
        if 0 <= y < h:
            img[y, x, :3] = rgb(["#2E241E", "#6A5244", "#8A6A50"][int(rng.integers(3))])
    img[:, :, :3][disc_wrap(w, h, cx - 2.0, cy - 2.2, 2.6)] = rgb("#8A6A50")
    # 火焰：朝左上喷
    for k in range(11):
        t = k / 10.0
        fx = cx - 1.0 - t * 6.5
        fy = cy - 1.0 - t * 7.5
        rad = 4.4 * (1.0 - t) + 0.6
        m = disc_wrap(w, h, fx, fy, rad)
        col = rgb(["#FFF6C0", "#FFD24A", "#FF8A2A", "#E84A1A"][min(int(t * 4), 3)])
        img[:, :, :3][m] = col
        img[:, :, 3][m] = 255.0
    return img


def main() -> None:
    os.makedirs(ART, exist_ok=True)
    print("事件素材：")
    for i in range(4):
        save(make_portal_frame(i), f"ev_portal_{i}.png", ART)
    save(make_meteor(), "ev_meteor.png", ART)

    # 事件横幅已挪到 gen_ui.py —— 它们带文字，要按语言出两套
    print("事件横幅： 见 gen_ui.py")


if __name__ == "__main__":
    main()
