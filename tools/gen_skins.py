#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 换装素材生成器（飞行器 + 驾驶员）

飞行器沿用现有的 64x64 图集约定：4 帧 32x32 横向排布（左上、右上、左下、右下），
这样引擎侧可以用同一段代码切 AtlasTexture，不用为每种飞机单独做 .tres。

驾驶员是 16x16 的单帧小人，画在飞行器背上。

另外产出菜单里用的预览方块（带边框），尺寸正好是原图 + 2 像素边。
"""
from __future__ import annotations

import os
import numpy as np

from gen_backgrounds import S, rgb, blank, upscale, save, ART
from PIL import Image


def save_raw(arr: np.ndarray, name: str) -> None:
    """不放大直接存。

    飞行器图集和驾驶员必须是**原生分辨率**（64x64 / 16x16）—— 引擎里整体还有一层
    6 倍放大，这里再乘 6 的话 Skins 按 32 像素切图就只能切到左上角一小块，
    结果是小鸟整个不显示（踩过一次）。
    """
    a = np.clip(arr, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "RGBA")
    im.save(os.path.join(ART, name))
    print(f"  -> {name:26s} {im.size[0]}x{im.size[1]}  (原生)")

CELL = 32          # 飞行器单帧边长
PILOT = 16         # 驾驶员边长


# ---------------------------------------------------------------- 画笔
def put(img: np.ndarray, x: int, y: int, color: str) -> None:
    h, w = img.shape[:2]
    if 0 <= x < w and 0 <= y < h:
        img[y, x, :3] = rgb(color)
        img[y, x, 3] = 255.0


def ell(img: np.ndarray, cx: float, cy: float, rx: float, ry: float, color: str) -> None:
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((xx - cx) / max(rx, 1e-6)) ** 2 + ((yy - cy) / max(ry, 1e-6)) ** 2 <= 1.0
    img[:, :, :3][m] = rgb(color)
    img[:, :, 3][m] = 255.0


def tri(img: np.ndarray, pts, color: str) -> None:
    """三角形填充（重心坐标法）。"""
    h, w = img.shape[:2]
    (x0, y0), (x1, y1), (x2, y2) = pts
    yy, xx = np.mgrid[0:h, 0:w]
    d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(d) < 1e-9:
        return
    a = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / d
    b = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / d
    c = 1 - a - b
    m = (a >= -0.02) & (b >= -0.02) & (c >= -0.02)
    img[:, :, :3][m] = rgb(color)
    img[:, :, 3][m] = 255.0


def frame_atlas(painter) -> np.ndarray:
    """把一个 (img, frame) 画笔铺成 64x64 的 4 帧图集。"""
    atlas = blank(CELL * 2, CELL * 2)
    for i in range(4):
        cell = blank(CELL, CELL)
        painter(cell, i)
        ox, oy = (i % 2) * CELL, (i // 2) * CELL
        sub = atlas[oy:oy + CELL, ox:ox + CELL]
        a = cell[:, :, 3:4] / 255.0
        sub[:, :, :3] = sub[:, :, :3] * (1 - a) + cell[:, :, :3] * a
        sub[:, :, 3:4] = np.maximum(sub[:, :, 3:4], cell[:, :, 3:4])
    return atlas


# ---------------------------------------------------------------- 飞行器
def paint_penguin(img, f):
    """胖企鹅：黑背白肚，翅膀上下扇。"""
    wing_y = (10, 6, 15, 6)[f]
    ell(img, 16, 20, 9, 10, "#1A1F2E")            # 身体
    ell(img, 16, 22, 6, 7, "#F2F6FA")             # 肚皮
    ell(img, 16, 11, 7, 7, "#1A1F2E")             # 头
    ell(img, 16, 12, 5, 5, "#F2F6FA")
    put(img, 13, 10, "#FFFFFF"); put(img, 13, 11, "#101728")
    put(img, 19, 10, "#FFFFFF"); put(img, 19, 11, "#101728")
    tri(img, [(16, 13), (23, 15), (16, 17)], "#F5A623")   # 喙
    ell(img, 6, wing_y, 3.2, 6.5, "#1A1F2E")      # 两翼
    ell(img, 26, wing_y, 3.2, 6.5, "#1A1F2E")
    ell(img, 13, 29, 3, 2, "#F5A623")             # 脚
    ell(img, 19, 29, 3, 2, "#F5A623")


def paint_rocket(img, f):
    """小火箭：机身 + 舷窗 + 尾焰，尾焰长度随帧变化。"""
    flame = (7, 10, 4, 10)[f]
    tri(img, [(16, 2), (23, 12), (9, 12)], "#E8465A")     # 头锥
    ell(img, 16, 18, 7, 8, "#F2F6FA")                     # 机身
    tri(img, [(9, 20), (4, 29), (9, 27)], "#E8465A")      # 尾翼
    tri(img, [(23, 20), (28, 29), (23, 27)], "#E8465A")
    ell(img, 16, 14, 3.4, 3.4, "#5AE0FF")                 # 舷窗
    ell(img, 16, 14, 2.0, 2.0, "#BFEFFF")
    for k in range(flame):                                # 尾焰
        ell(img, 16, 27 + k, 4 - k * 0.28, 1.1, "#FFD24A" if k < flame - 2 else "#FF8A2A")
    put(img, 16, 28, "#FFF6C0")


def paint_bat(img, f):
    """蝙蝠：翅膀三档张开。"""
    span = (13, 8, 15, 8)[f]
    drop = (4, 9, 2, 9)[f]
    tri(img, [(14, 16), (14 - span, 16 - drop), (14 - span + 3, 16 + drop + 5)], "#4A2A6E")
    tri(img, [(18, 16), (18 + span, 16 - drop), (18 + span - 3, 16 + drop + 5)], "#4A2A6E")
    ell(img, 16, 18, 5, 7, "#2E1A4A")                     # 身体
    ell(img, 16, 12, 5, 5, "#3A2258")                     # 头
    tri(img, [(12, 8), (13, 3), (16, 8)], "#4A2A6E")      # 耳朵
    tri(img, [(20, 8), (19, 3), (16, 8)], "#4A2A6E")
    put(img, 14, 11, "#FF5A8A"); put(img, 18, 11, "#FF5A8A")
    put(img, 14, 12, "#FFD24A"); put(img, 18, 12, "#FFD24A")


def paint_paper(img, f):
    """纸飞机：折痕随帧翻动。"""
    fold = (3, 0, 6, 0)[f]
    tri(img, [(2, 16), (30, 16 - fold), (30, 16 + fold)], "#F2F6FA")
    tri(img, [(2, 16), (30, 16 + fold), (18, 28)], "#C8D4E4")
    tri(img, [(2, 16), (18, 28), (16, 20)], "#9FB0C8")
    put(img, 28, 16, "#FFFFFF")


def paint_ufo(img, f):
    """飞碟：碟身 + 玻璃罩 + 底部光束。"""
    beam = (9, 6, 11, 6)[f]
    for k in range(beam):
        w = 3 + k * 0.9
        ell(img, 16, 22 + k, w, 0.8, "#9FF8FF" if k % 2 == 0 else "#5AE0FF")
    ell(img, 16, 20, 14, 4.5, "#8A94A8")                  # 碟身
    ell(img, 16, 19, 14, 3.0, "#C8D4E4")
    ell(img, 16, 13, 7, 6, "#5AC8E0")                     # 玻璃罩
    ell(img, 16, 13, 5.5, 4.5, "#9FF8FF")
    ell(img, 16, 14, 2.6, 3.0, "#3FE0A0")                 # 里面的小外星人
    put(img, 15, 13, "#101728"); put(img, 18, 13, "#101728")
    for x in (5, 11, 21, 27):                             # 舷灯
        put(img, x, 21, "#FBF236" if (x + f) % 4 < 2 else "#FF5A8A")


AIRCRAFT = {
    "penguin": paint_penguin,
    "rocket": paint_rocket,
    "bat": paint_bat,
    "paper": paint_paper,
    "ufo": paint_ufo,
}


# ---------------------------------------------------------------- 驾驶员
def paint_pilot(kind: str) -> np.ndarray:
    img = blank(PILOT, PILOT)
    if kind == "none":
        return img
    if kind == "cat":
        ell(img, 8, 9, 5, 5, "#F0A860")                   # 头
        tri(img, [(4, 6), (5, 1), (8, 5)], "#F0A860")     # 耳朵
        tri(img, [(12, 6), (11, 1), (8, 5)], "#F0A860")
        put(img, 6, 9, "#101728"); put(img, 10, 9, "#101728")
        put(img, 8, 11, "#FF8AA8")                        # 鼻子
        for dx in (-3, 0, 3):                             # 胡须
            put(img, 8 + dx, 10, "#5A3A20")
    elif kind == "dog":
        ell(img, 8, 9, 5, 5, "#B07A48")
        ell(img, 4, 6, 2.2, 4, "#8A5A32")                 # 垂耳
        ell(img, 12, 6, 2.2, 4, "#8A5A32")
        put(img, 6, 9, "#101728"); put(img, 10, 9, "#101728")
        ell(img, 8, 12, 2.4, 1.8, "#5A3A20")              # 鼻子
    elif kind == "robot":
        for x in range(4, 13):
            for y in range(4, 14):
                put(img, x, y, "#9FB0C8")
        for x in range(5, 12):
            for y in range(5, 9):
                put(img, x, y, "#3FE0E0")                 # 面罩
        put(img, 6, 7, "#FF5A8A"); put(img, 10, 7, "#FF5A8A")
        put(img, 8, 1, "#FBF236"); put(img, 8, 2, "#9FB0C8")   # 天线
        put(img, 3, 8, "#5A6478"); put(img, 13, 8, "#5A6478")  # 耳朵
    elif kind == "alien":
        ell(img, 8, 8, 5.5, 6.5, "#7AE07A")               # 大绿头
        ell(img, 5, 8, 2.2, 3.2, "#101728")               # 大眼
        ell(img, 11, 8, 2.2, 3.2, "#101728")
        put(img, 5, 8, "#FFFFFF"); put(img, 11, 8, "#FFFFFF")
        put(img, 7, 12, "#3AA03A"); put(img, 9, 12, "#3AA03A")
        put(img, 4, 2, "#7AE07A"); put(img, 12, 2, "#7AE07A")  # 触角
        put(img, 4, 1, "#FBF236"); put(img, 12, 1, "#FBF236")
    elif kind == "chick":
        ell(img, 8, 9, 5, 5, "#FBE06A")
        put(img, 6, 8, "#101728"); put(img, 10, 8, "#101728")
        tri(img, [(8, 10), (11, 11), (8, 12)], "#F5A623")
        put(img, 8, 4, "#FBE06A"); put(img, 7, 3, "#FBE06A"); put(img, 9, 3, "#FBE06A")
        put(img, 6, 14, "#F5A623"); put(img, 10, 14, "#F5A623")
    return img


PILOTS = ["none", "cat", "dog", "robot", "alien", "chick"]


# ---------------------------------------------------------------- 预览方块
def preview(src: np.ndarray, pad: int = 2) -> np.ndarray:
    """给原图套一圈 2 像素亮边，做成菜单里可点的方块。"""
    h, w = src.shape[:2]
    out = blank(w + pad * 2, h + pad * 2)
    out[:, :, :3] = rgb("#252D33")
    out[:, :, 3] = 235.0
    out[:pad, :, :3] = rgb("#8FA0A8"); out[-pad:, :, :3] = rgb("#8FA0A8")
    out[:, :pad, :3] = rgb("#8FA0A8"); out[:, -pad:, :3] = rgb("#8FA0A8")
    sub = out[pad:pad + h, pad:pad + w]
    a = src[:, :, 3:4] / 255.0
    sub[:, :, :3] = sub[:, :, :3] * (1 - a) + src[:, :, :3] * a
    sub[:, :, 3:4] = np.maximum(sub[:, :, 3:4], src[:, :, 3:4])
    return out


BADGE = 16


def make_badge(label: str, fill: str, edge: str) -> np.ndarray:
    """头顶的玩家标志：一个圆牌 + P1/P2 字样（用自带的 5x7 点阵字体）。"""
    from gen_ui import pixel_mask
    img = blank(BADGE, BADGE)
    ell(img, 7.5, 7.5, 7.4, 7.4, edge)          # 外圈
    ell(img, 7.5, 7.5, 6.1, 6.1, fill)          # 内芯
    ell(img, 6.0, 5.5, 2.6, 2.0, "#FFFFFF")     # 高光
    m = pixel_mask(label, 1)                     # 11x7
    oy, ox = 4, (BADGE - m.shape[1]) // 2
    for y in range(m.shape[0]):
        for x in range(m.shape[1]):
            if m[y, x]:
                put(img, ox + x, oy + y, "#101728")
    return img


def main() -> None:
    os.makedirs(ART, exist_ok=True)
    from gen_backgrounds import PROJ
    from PIL import Image

    print("飞行器：")
    for name, painter in AIRCRAFT.items():
        atlas = frame_atlas(painter)
        save_raw(atlas, f"bird_{name}.png")
        save(preview(atlas[0:CELL, 0:CELL]), f"skin_bird_{name}.png", ART)

    # 经典蓝鸟直接沿用原来的图集，只补一张预览方块
    classic = np.array(Image.open(os.path.join(ART, "bird_blue.png")).convert("RGBA"),
                       dtype=np.float32)
    save(preview(classic[0:CELL, 0:CELL]), "skin_bird_classic.png", ART)
    print("  （经典蓝鸟沿用现成图集）")

    print("玩家标志：")
    save_raw(make_badge("P1", "#5AE0FF", "#1B4A63"), "badge_p1.png")
    save_raw(make_badge("P2", "#FFB04A", "#6B3A10"), "badge_p2.png")
    save_raw(make_badge("AI", "#9AE07A", "#2E5A22"), "badge_bot.png")

    print("驾驶员：")
    for name in PILOTS:
        img = paint_pilot(name)
        save_raw(img, f"pilot_{name}.png")
        save(preview(img), f"skin_pilot_{name}.png", ART)


if __name__ == "__main__":
    main()
