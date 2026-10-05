#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 道具与特效素材

三类道具（32x32 原生分辨率，和飞行器一样整体由引擎放大 6 倍）：
    pu_magnet  磁铁      吸金币
    pu_shield  护盾      挡一次撞击
    pu_burst   金币爆发  原地炸出一圈金币

外加：
    fx_shield  护盾生效时包在小鸟外面的泡泡（48x48）
    ui_*       连击 / 道具状态的文字标签
"""
from __future__ import annotations

import os
import numpy as np

from gen_backgrounds import rgb, blank, ART
from gen_ui import make_label
from gen_skins import put, ell, tri, save_raw, save


ICON = 32
BUBBLE = 48


def glow(img: np.ndarray, color: str, alpha: float = 0.55) -> None:
    """圆盘底光，让道具在花花绿绿的背景里也能一眼看到。"""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    cx = cy = (w - 1) / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (w * 0.5)
    k = np.clip(1.0 - r, 0.0, 1.0) ** 1.6 * alpha
    col = rgb(color).astype(np.float32)
    img[:, :, :3] = img[:, :, :3] * (1 - k[..., None]) + col * k[..., None]
    img[:, :, 3] = np.maximum(img[:, :, 3], np.clip(k * 255.0 * 2.2, 0, 255))


def make_magnet() -> np.ndarray:
    img = blank(ICON, ICON)
    glow(img, "#FF5A5A")
    # U 形磁铁：两条竖臂 + 底部圆弧
    for y in range(6, 22):
        for x in (9, 10, 11, 20, 21, 22):
            put(img, x, y, "#E8465A")
    ell(img, 15.5, 21, 6.6, 6.0, "#E8465A")
    ell(img, 15.5, 21, 3.6, 3.2, "#101728")
    # 两极：银白 + 蓝红
    for x in (9, 10, 11):
        put(img, x, 6, "#C8D4E4"); put(img, x, 7, "#8FA0A8")
    for x in (20, 21, 22):
        put(img, x, 6, "#C8D4E4"); put(img, x, 7, "#8FA0A8")
    ell(img, 10, 7, 1.6, 1.4, "#5AE0FF")
    ell(img, 21, 7, 1.6, 1.4, "#FF5A8A")
    return img


def make_shield() -> np.ndarray:
    img = blank(ICON, ICON)
    glow(img, "#5AC8FF")
    # 盾牌：上方矩形 + 下方三角尖
    for y in range(6, 18):
        for x in range(8, 24):
            put(img, x, y, "#3F8FE0")
    tri(img, [(8, 17), (23, 17), (15.5, 28)], "#3F8FE0")
    for y in range(7, 17):
        for x in range(9, 23):
            put(img, x, y, "#5AB0FF")
    tri(img, [(9, 17), (22, 17), (15.5, 26)], "#5AB0FF")
    # 中间的十字
    for y in range(11, 21):
        put(img, 15, y, "#EAF6FF"); put(img, 16, y, "#EAF6FF")
    for x in range(12, 20):
        put(img, x, 14, "#EAF6FF"); put(img, x, 15, "#EAF6FF")
    return img


def make_burst() -> np.ndarray:
    img = blank(ICON, ICON)
    glow(img, "#FFD24A")
    # 八角星爆 + 中间一枚金币
    import math
    for a in range(16):
        ang = a * math.pi / 8.0
        for r in range(4, 14):
            x = int(16 + math.cos(ang) * r)
            y = int(16 + math.sin(ang) * r)
            if a % 2 == 0 or r < 8:
                put(img, x, y, "#FBF236" if a % 2 == 0 else "#FFF6C0")
    ell(img, 15.5, 15.5, 6.0, 6.0, "#D9A62E")
    ell(img, 15.5, 15.5, 4.6, 4.6, "#FBF236")
    ell(img, 14, 14, 2.0, 2.0, "#FFF6CE")
    return img


def make_bubble() -> np.ndarray:
    """护盾生效时罩住小鸟的泡泡。半透明，只有一圈亮边看得清。"""
    img = blank(BUBBLE, BUBBLE)
    yy, xx = np.mgrid[0:BUBBLE, 0:BUBBLE]
    cx = cy = (BUBBLE - 1) / 2.0
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (BUBBLE * 0.5 - 1)
    fill = d <= 1.0
    ring = (d > 0.86) & (d <= 1.0)
    inner = (d > 0.78) & (d <= 0.86)
    img[:, :, :3][fill] = rgb("#5AC8FF")
    img[:, :, 3][fill] = 38.0
    img[:, :, :3][inner] = rgb("#9FE8FF")
    img[:, :, 3][inner] = 150.0
    img[:, :, :3][ring] = rgb("#DFF6FF")
    img[:, :, 3][ring] = 235.0
    # 左上高光弧
    hi = ((xx - cx + 9) ** 2 + (yy - cy + 9) ** 2) <= 20.0
    img[:, :, :3][hi & ring] = rgb("#FFFFFF")
    return img


def main() -> None:
    os.makedirs(ART, exist_ok=True)
    print("道具：")
    save_raw(make_magnet(), "pu_magnet.png")
    save_raw(make_shield(), "pu_shield.png")
    save_raw(make_burst(), "pu_burst.png")
    save_raw(make_bubble(), "fx_shield.png")

    print("道具标签：")


if __name__ == "__main__":
    main()