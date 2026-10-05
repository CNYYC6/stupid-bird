#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 界面素材生成器

两套字形混用：
  * 英文标题 / HUD 数字：自带 5x7 点阵字体，笔画均匀、最像游戏像素字；
  * 中文：用系统黑体渲染成 12/16px 位图再阈值二值化，笔画被"压"成硬边像素，
    不会像矢量字那样半透明发灰，和背景是同一套颗粒。

（Godot 默认字体不含中文字形，直接写中文会变豆腐块，所以中文一律烘进贴图。）
"""
from __future__ import annotations

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

S = 6
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, ".."))
ART = os.path.join(PROJ, "art")

# ------------------------------------------------------------------ 中文字形
CJK_CANDIDATES = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "C:/Windows/Fonts/msyh.ttc",
]
_CJK_CACHE: dict = {}


def load_cjk(size: int):
    if size in _CJK_CACHE:
        return _CJK_CACHE[size]
    for path in CJK_CANDIDATES:
        if os.path.exists(path):
            try:
                f = ImageFont.truetype(path, size)
                _CJK_CACHE[size] = f
                print(f"     中文点阵字体: {os.path.basename(path)} @ {size}px")
                return f
            except Exception:
                continue
    raise RuntimeError("找不到可用的中文字体，请把路径加进 CJK_CANDIDATES")


def cjk_mask(text: str, size: int, threshold: int = 110) -> np.ndarray:
    """字符串 -> 1-bit 蒙版：系统字体渲染 -> 阈值二值化 -> 裁掉空白边。"""
    font = load_cjk(size)
    pad = size
    canvas = Image.new("L", (size * (len(text) + 2) + pad * 2, size * 3), 0)
    ImageDraw.Draw(canvas).text((pad, size // 2), text, font=font, fill=255)
    m = np.array(canvas) > threshold
    ys, xs = np.where(m)
    if len(xs) == 0:
        return np.zeros((size, size), dtype=bool)
    return m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ------------------------------------------------------------------ 5x7 点阵字体
FONT = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["#..#.", "#..#.", "#..#.", "#####", "...#.", "...#.", "...#."],
    "5": ["#####", "#....", "#....", "####.", "....#", "#...#", ".###."],
    "6": [".###.", "#...#", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "#...#", ".###."],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}
GLYPH_W, GLYPH_H, TRACKING = 5, 7, 1


def pixel_mask(text: str, scale: int) -> np.ndarray:
    text = text.upper()
    cols = len(text) * (GLYPH_W + TRACKING) - TRACKING
    m = np.zeros((GLYPH_H, cols), dtype=bool)
    x = 0
    for ch in text:
        g = FONT.get(ch, FONT[" "])
        for gy in range(GLYPH_H):
            for gx in range(GLYPH_W):
                if g[gy][gx] == "#":
                    m[gy, x + gx] = True
        x += GLYPH_W + TRACKING
    return np.repeat(np.repeat(m, scale, axis=0), scale, axis=1)


# ------------------------------------------------------------------ 工具
def dilate(m: np.ndarray, r: int = 1) -> np.ndarray:
    p = np.pad(m, r, constant_values=False)
    out = p.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(p, dy, axis=0), dx, axis=1)
    return out[r:-r, r:-r]


def rgba(h: str, a: int = 255) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)] + [a], dtype=np.float32)


def save(img: np.ndarray, name: str) -> None:
    a = np.clip(img, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "RGBA")
    up = im.resize((im.width * S, im.height * S), Image.NEAREST)
    up.save(os.path.join(ART, name))
    print(f"  -> {name:26s} {up.size[0]}x{up.size[1]}")


def paste_mask(h: int, w: int, mask: np.ndarray, oy: int, ox: int) -> np.ndarray:
    body = np.zeros((h, w), dtype=bool)
    body[oy:oy + mask.shape[0], ox:ox + mask.shape[1]] = mask
    return body


# ------------------------------------------------------------------ 各类素材
def make_title(text: str = "STUPID BIRD", scale: int = 3) -> np.ndarray:
    mask = pixel_mask(text, scale)
    pad = 4 * scale
    h, w = mask.shape[0] + pad * 2, mask.shape[1] + pad * 2
    body = paste_mask(h, w, mask, pad, pad)

    shadow = np.roll(np.roll(dilate(body, scale // 2), scale, axis=0), scale, axis=1)
    outline = dilate(body, max(1, scale // 3)) & ~body

    img = np.zeros((h, w, 4), dtype=np.float32)
    img[shadow & ~body] = rgba("#141C33")
    img[outline] = rgba("#101728")

    top, mid, bot = rgba("#FFFFFF"), rgba("#FFF3C0"), rgba("#FBF236")
    grad = np.zeros((h, 3), dtype=np.float32)
    for y in range(h):
        t = y / max(h - 1, 1)
        grad[y] = (top[:3] * (1 - t * 2) + mid[:3] * (t * 2)) if t < 0.5 else \
                  (mid[:3] * (1 - (t - 0.5) * 2) + bot[:3] * ((t - 0.5) * 2))
    img[:, :, :3][body] = grad[np.where(body)[0]]
    img[:, :, 3][shadow | outline | body] = 255.0
    return img


def panel(w: int, h: int, fill: str, fill_a: int, border: str, top_hi: str) -> np.ndarray:
    img = np.zeros((h, w, 4), dtype=np.float32)
    img[:] = rgba(fill, fill_a)
    b = 2
    img[:b, :] = rgba(border)
    img[-b:, :] = rgba(border)
    img[:, :b] = rgba(border)
    img[:, -b:] = rgba(border)
    img[b:b + 2, b:-b] = rgba(top_hi)
    img[-b - 2:-b, b:-b] = rgba("#12181C", 190)
    return img


def make_button(label: str, hover: bool = False, pressed: bool = False,
                size: int = 16, pad_x: int = 18, pad_y: int = 9) -> np.ndarray:
    mask = cjk_mask(label, size)
    w = mask.shape[1] + pad_x * 2
    h = mask.shape[0] + pad_y * 2
    if pressed:
        img = panel(w, h, "#1B2126", 235, "#FBF236", "#2A3238")
    elif hover:
        img = panel(w, h, "#2F3A42", 245, "#FBF236", "#4A5A64")
    else:
        img = panel(w, h, "#252D33", 220, "#8FA0A8", "#3A464E")

    body = paste_mask(h, w, mask, pad_y, pad_x)
    fg = rgba("#FBF236") if (hover or pressed) else rgba("#E8EEF2")
    img[:, :, :3][body] = fg[:3]
    img[:, :, 3][body] = 255.0
    return img


def make_label(text: str, size: int = 12, color: str = "#E4EDF5", pad: int = 3,
               outline: int = 1) -> np.ndarray:
    """带描边的标签贴图，用于 HUD 与提示文字。"""
    mask = cjk_mask(text, size)
    h, w = mask.shape[0] + pad * 2, mask.shape[1] + pad * 2
    img = np.zeros((h, w, 4), dtype=np.float32)
    body = paste_mask(h, w, mask, pad, pad)
    edge = dilate(body, outline) & ~body
    img[edge] = rgba("#101728", 235)
    img[:, :, :3][body] = rgba(color)[:3]
    img[:, :, 3][body | edge] = 255.0
    return img


def make_digit(d: int, scale: int = 2, color: str = "#FBF236", pad: int = 2,
                outline: int = 1) -> np.ndarray:
    mask = pixel_mask(str(d), scale)
    h, w = mask.shape[0] + pad * 2, mask.shape[1] + pad * 2
    img = np.zeros((h, w, 4), dtype=np.float32)
    body = paste_mask(h, w, mask, pad, pad)
    edge = dilate(body, outline) & ~body
    img[edge] = rgba("#101728", 235)
    img[:, :, :3][body] = rgba(color)[:3]
    img[:, :, 3][body | edge] = 255.0
    return img


def make_shade(w: int = 320, h: int = 180) -> np.ndarray:
    img = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        t = y / (h - 1)
        img[y, :, 3] = np.clip(34 + 52 * (1 - abs(t - 0.42) / 0.58), 0, 96)
    return img


def main() -> None:
    print("生成开始界面素材：")
    save(make_title("STUPID BIRD", 3), "ui_title.png")
    save(make_button("开始游戏"), "ui_btn_start.png")
    save(make_button("开始游戏", hover=True), "ui_btn_start_hover.png")
    save(make_button("开始游戏", pressed=True), "ui_btn_start_pressed.png")
    save(make_button("退出游戏"), "ui_btn_quit.png")
    save(make_button("退出游戏", hover=True), "ui_btn_quit_hover.png")
    save(make_button("退出游戏", pressed=True), "ui_btn_quit_pressed.png")
    # 本作没有左右操作，A/D 已经删掉：提示里也不要再出现，否则玩家会一直按
    save(make_label("空格 / W 爬升    ENTER 无敌冲刺    R 重来    ESC 返回", 12), "ui_hint.png")
    save(make_label("按住空格爬升，ENTER 无敌冲刺可以硬穿路障。", 12), "ui_tip.png")
    save(make_label("最远记录", 12, "#FBF236"), "ui_best_label.png")
    save(make_label("金币", 12), "ui_coin_label.png")
    save(make_label("撞毁了！", 26, "#F2724E", pad=6, outline=2), "ui_over_title.png")
    save(make_button("再来一次"), "ui_btn_retry.png")
    save(make_button("再来一次", hover=True), "ui_btn_retry_hover.png")
    save(make_button("再来一次", pressed=True), "ui_btn_retry_pressed.png")
    save(make_button("返回主菜单"), "ui_btn_menu.png")
    save(make_button("返回主菜单", hover=True), "ui_btn_menu_hover.png")
    save(make_button("返回主菜单", pressed=True), "ui_btn_menu_pressed.png")

    # 机哥模式的难度档位（按钮小一号，免得整行超宽）
    for tag, text in (("lv0", "臭人机"), ("lv1", "普通人机"), ("lv2", "机哥")):
        save(make_button(text, size=12), f"ui_btn_{tag}.png")
        save(make_button(text, size=12, hover=True), f"ui_btn_{tag}_hover.png")
        save(make_button(text, size=12, pressed=True), f"ui_btn_{tag}_pressed.png")

    # 换装间
    save(make_button("换装"), "ui_btn_dress.png")
    save(make_button("换装", hover=True), "ui_btn_dress_hover.png")
    save(make_button("换装", pressed=True), "ui_btn_dress_pressed.png")
    save(make_label("换装间", 26, "#FFB0E0", pad=6, outline=2), "ui_dress_title.png")
    save(make_label("飞行器", 12, "#FBF236"), "ui_label_aircraft.png")
    save(make_label("驾驶员", 12, "#9FF8FF"), "ui_label_pilot.png")
    save(make_label("正在编辑", 12), "ui_label_editing.png")
    for tag, text in (("p1", "玩家 1"), ("p2", "玩家 2")):
        save(make_button(text, size=12), f"ui_btn_{tag}.png")
        save(make_button(text, size=12, hover=True), f"ui_btn_{tag}_hover.png")
        save(make_button(text, size=12, pressed=True), f"ui_btn_{tag}_pressed.png")
    save(make_button("返回"), "ui_btn_close.png")
    save(make_button("返回", hover=True), "ui_btn_close_hover.png")
    save(make_button("返回", pressed=True), "ui_btn_close_pressed.png")

    # 模式切换按钮：按钮文字本身就表明当前模式，省掉一行"当前：xxx"的标签
    for tag, text in (("solo", "模式：单人"), ("coop", "模式：双人"), ("bot", "机哥带你飞")):
        save(make_button(text), f"ui_btn_{tag}.png")
        save(make_button(text, hover=True), f"ui_btn_{tag}_hover.png")
        save(make_button(text, pressed=True), f"ui_btn_{tag}_pressed.png")

    save(make_shade(), "ui_shade.png")

    print("生成 HUD 素材：")
    save(make_label("距离", 12), "ui_dist_label.png")
    save(make_label("米", 12), "ui_meter_label.png")
    # 右下角的无敌冲刺能量条：标题常驻，右侧状态字随冲刺/冷却切换
    save(make_label("无敌冲刺", 12), "ui_dash_label.png")
    save(make_label("就绪", 12, "#FBF236"), "ui_dash_ready.png")
    save(make_label("发动中", 12, "#FFC93C"), "ui_dash_active.png")
    save(make_label("冷却中", 12, "#93A3B0"), "ui_dash_cool.png")
    for d in range(10):
        save(make_digit(d), f"ui_digit_{d}.png")


if __name__ == "__main__":
    main()
