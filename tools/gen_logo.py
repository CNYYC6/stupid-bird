#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 开屏标志生成器

把 "YYCHRER" 七个字母逐个烘成贴图：用系统的手写体渲染 → 阈值二值化 → 整数倍放大。
放大放在二值化**之后**，边缘才会是硬邦邦的方块，跟游戏其它美术是同一套颗粒。

每个字母独立成一张图，开屏动画才能一个一个放出来。
另外给每个字母一点点倾斜和上下错位 —— 手写感主要就来自"没对齐"。
"""
from __future__ import annotations

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, ".."))
ART = os.path.join(PROJ, "art")

WORD = "YYCHRER"
## 手写体候选，按优先级找
FONTS = [
    "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf",
    "/System/Library/Fonts/Supplemental/ChalkboardSE.ttc",
    "/System/Library/Fonts/Supplemental/Chalkduster.ttf",
    "/System/Library/Fonts/Supplemental/Comic Sans MS Bold.ttf",
]
FONT_SIZE = 52
## 二值化之后放大这么多倍 —— 这就是"像素"的大小
UPSCALE = 4
THRESHOLD = 120
## 每个字母的倾斜（度），按顺序给，制造手写的不齐感
TILTS = [-7.0, 4.0, -4.0, 6.0, -5.0, 3.0, -8.0]
## 上下错位（原生像素）
OFFSETS = [2, -3, 1, -2, 3, -1, 2]
INK = (251, 243, 208)
EDGE = (16, 23, 40)


def find_font() -> str:
    for p in FONTS:
        if os.path.exists(p):
            print(f"     手写体: {os.path.basename(p)}")
            return p
    raise RuntimeError("找不到可用的手写体字体")


def glyph_mask(font_path: str, ch: str) -> np.ndarray:
    """单个字母 -> 1-bit 蒙版，裁到墨迹边界。"""
    font = ImageFont.truetype(font_path, FONT_SIZE)
    canvas = Image.new("L", (FONT_SIZE * 4, FONT_SIZE * 4), 0)
    ImageDraw.Draw(canvas).text((FONT_SIZE, FONT_SIZE), ch, font=font, fill=255)
    m = np.array(canvas) > THRESHOLD
    ys, xs = np.where(m)
    if len(xs) == 0:
        raise RuntimeError(f"字母 {ch} 渲染为空")
    return m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def tint(mask: np.ndarray) -> np.ndarray:
    """蒙版 -> 带描边的彩色图（RGBA）"""
    h, w = mask.shape
    img = np.zeros((h, w, 4), dtype=np.float32)
    body = mask
    edge = np.zeros_like(mask)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
        edge |= np.roll(np.roll(mask, dy, 0), dx, 1)
    edge &= ~body
    img[:, :, :3][body] = np.array(INK, dtype=np.float32)
    img[:, :, :3][edge] = np.array(EDGE, dtype=np.float32)
    img[:, :, 3][body | edge] = 255.0
    return img


def main() -> None:
    font_path = find_font()
    os.makedirs(os.path.join(ART, "logo"), exist_ok=True)
    print("开屏标志：")
    heights: list[int] = []
    raw: list[np.ndarray] = []
    for i, ch in enumerate(WORD):
        m = glyph_mask(font_path, ch)
        raw.append(m)
        heights.append(m.shape[0])

    # 统一画布高度，保证七个字母在同一条基线上
    H = max(heights) + 6
    for i, ch in enumerate(WORD):
        m = raw[i]
        pad_top = (H - m.shape[0]) // 2 + OFFSETS[i]
        canvas = np.zeros((H, m.shape[1] + 4), dtype=bool)
        y0 = max(pad_top, 0)
        y1 = min(pad_top + m.shape[0], H)
        canvas[y0:y1, 2:2 + m.shape[1]] = m[y0 - pad_top:y1 - pad_top]
        img = tint(canvas)
        pil = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")
        # 倾斜一点点 —— 手写感的关键
        pil = pil.rotate(TILTS[i], resample=Image.BICUBIC, expand=True)
        a = np.array(pil)
        a[a[:, :, 3] < 110] = 0
        pil = Image.fromarray(a, "RGBA")
        # 二值化之后才放大，边缘才是方块
        up = pil.resize((pil.width * UPSCALE, pil.height * UPSCALE), Image.NEAREST)
        name = f"logo/letter_{i}.png"
        up.save(os.path.join(ART, name))
        print(f"  -> {name:22s} {up.size[0]}x{up.size[1]}")


if __name__ == "__main__":
    main()
