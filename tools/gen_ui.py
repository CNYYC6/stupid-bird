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


def save(img: np.ndarray, name: str, sub: str = "") -> None:
    a = np.clip(img, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "RGBA")
    up = im.resize((im.width * S, im.height * S), Image.NEAREST)
    d = os.path.join(ART, "ui", sub) if sub else ART
    os.makedirs(d, exist_ok=True)
    up.save(os.path.join(d, name))
    print(f"  -> {sub + '/' if sub else '':6s}{name:26s} {up.size[0]}x{up.size[1]}")


def paste_mask(h: int, w: int, mask: np.ndarray, oy: int, ox: int) -> np.ndarray:
    body = np.zeros((h, w), dtype=bool)
    body[oy:oy + mask.shape[0], ox:ox + mask.shape[1]] = mask
    return body


# ------------------------------------------------------------------ 各类素材
def text_mask(text: str, size: int) -> np.ndarray:
    """纯 ASCII 的文案走自带的 5x7 点阵（笔画均匀，最像游戏像素字）；
    含中文的走系统黑体二进制化。两种字形在同一个界面上混用不会打架，
    因为点阵的缩放是按 size 换算的，字高和中文对得上。"""
    if all(ord(ch) < 128 for ch in text):
        scale = max(1, int(round(size / 7.0)))
        return pixel_mask(text, scale)
    return cjk_mask(text, size)


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
    mask = text_mask(label, size)
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
    mask = text_mask(text, size)
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


# ------------------------------------------------------------------ 文案表
# 界面文字全部烘进贴图的时代，多语言就是"同一张图生成两套"。
# 这里集中放所有文案，跑一次脚本产出 art/ui/en/ 和 art/ui/zh/ 两整套，
# 运行期按语言换路径即可（见 scripts/ui_lang.gd）。默认英语。
STRINGS: dict = {
    "en": {
        "title": "STUPID BIRD",
        "btn_start": "START", "btn_quit": "QUIT",
        "hint": "W climb    E dash    R retry    ESC back",
        "tip": "Hold W to climb. E dashes through obstacles.",
        "best_label": "BEST", "coin_label": "COINS",
        "over_title": "CRASHED!",
        "btn_retry": "RETRY", "btn_menu": "MAIN MENU",
        "btn_lv0": "ROOKIE", "btn_lv1": "REGULAR", "btn_lv2": "ACE",
        "btn_skins": "SKINS", "skin_title": "SKINS",
        "label_aircraft": "AIRCRAFT", "label_pilot": "PILOT",
        "label_editing": "EDITING",
        "btn_p1": "PLAYER 1", "btn_p2": "PLAYER 2",
        "btn_close": "BACK",
        "btn_solo": "MODE: SOLO", "btn_coop": "MODE: CO-OP", "btn_bot": "AI COPILOT",
        "btn_settings": "SETTINGS", "settings_title": "SETTINGS",
        "label_language": "LANGUAGE", "label_window": "DISPLAY",
        "label_resolution": "RESOLUTION",
        "btn_en": "English", "btn_zh": "\u4e2d\u6587",
        "btn_windowed": "WINDOWED", "btn_fullscreen": "FULLSCREEN",
        "res0": "1280 x 720", "res1": "1600 x 900", "res2": "1920 x 1080",
        "dist_label": "DIST", "meter_label": "M",
        "dash_label": "DASH", "dash_ready": "READY",
        "dash_active": "ACTIVE", "dash_cool": "COOLING",
        "combo_label": "COMBO", "pu_magnet": "MAGNET", "pu_shield": "SHIELD",
        "revive_label": "REVIVE IN", "skip_hint": "PRESS ANY KEY TO SKIP",
        "also_try": "Also try Bililearn",
        "pu_burst": "COIN BURST", "shield_ready": "SHIELD ON",
        # 事件横幅与换场横幅也是带文字的，同样要出两套
        "ev_portal_t": "PORTAL!", "ev_portal_s": "Jump in - it's all coins",
        "ev_coin_rain_t": "COIN RAIN!", "ev_coin_rain_s": "Catch them all",
        "ev_low_g_t": "MOON GRAVITY!", "ev_low_g_s": "Float away",
        "ev_high_g_t": "HEAVY GRAVITY!", "ev_high_g_s": "Hold on tight",
        "ev_turbo_t": "FREE DASH!", "ev_turbo_s": "It's on the house",
        "ev_meteor_t": "METEOR SHOWER!", "ev_meteor_s": "Dodge!",
        "ev_double_t": "DOUBLE COINS!", "ev_double_s": "Cha-ching",
        "ev_fever_t": "COIN REALM!", "ev_fever_s": "20 seconds - go wild!",
        "ev_sec": "S",
        "w_sky_t": "CLEAR SKIES", "w_sky_s": "Warm up",
        "w_space_t": "OUTER SPACE", "w_space_s": "Low gravity - float",
        "w_jungle_t": "JUNGLE", "w_jungle_s": "Dense trees ahead",
        "w_dream_t": "DREAM WORLD", "w_dream_s": "Physics optional",
        "w_upside_t": "UPSIDE DOWN", "w_upside_s": "Trust nothing",
        "w_coin_t": "COIN REALM", "w_coin_s": "20 seconds - go wild!",
    },
    "zh": {
        "title": "STUPID BIRD",
        "btn_start": "\u5f00\u59cb\u6e38\u620f", "btn_quit": "\u9000\u51fa\u6e38\u620f",
        "hint": "W \u722c\u5347    E \u65e0\u654c\u51b2\u523a    R \u91cd\u6765    ESC \u8fd4\u56de",
        "tip": "\u6309\u4f4f W \u722c\u5347\uff0cE \u65e0\u654c\u51b2\u523a\u53ef\u4ee5\u786c\u7a7f\u8def\u969c\u3002",
        "best_label": "\u6700\u8fdc\u8bb0\u5f55", "coin_label": "\u91d1\u5e01",
        "over_title": "\u649e\u6bc1\u4e86\uff01",
        "btn_retry": "\u518d\u6765\u4e00\u6b21", "btn_menu": "\u8fd4\u56de\u4e3b\u83dc\u5355",
        "btn_lv0": "\u81ed\u4eba\u673a", "btn_lv1": "\u666e\u901a\u4eba\u673a",
        "btn_lv2": "\u673a\u54e5",
        "btn_skins": "\u76ae\u80a4", "skin_title": "\u76ae\u80a4",
        "label_aircraft": "\u98de\u884c\u5668", "label_pilot": "\u9a7e\u9a76\u5458",
        "label_editing": "\u6b63\u5728\u7f16\u8f91",
        "btn_p1": "\u73a9\u5bb6 1", "btn_p2": "\u73a9\u5bb6 2",
        "btn_close": "\u8fd4\u56de",
        "btn_solo": "\u6a21\u5f0f\uff1a\u5355\u4eba",
        "btn_coop": "\u6a21\u5f0f\uff1a\u53cc\u4eba",
        "btn_bot": "\u673a\u54e5\u5e26\u4f60\u98de",
        "btn_settings": "\u8bbe\u7f6e", "settings_title": "\u8bbe\u7f6e",
        "label_language": "\u8bed\u8a00", "label_window": "\u663e\u793a",
        "label_resolution": "\u5206\u8fa8\u7387",
        "btn_en": "English", "btn_zh": "\u4e2d\u6587",
        "btn_windowed": "\u7a97\u53e3", "btn_fullscreen": "\u5168\u5c4f",
        "res0": "1280 x 720", "res1": "1600 x 900", "res2": "1920 x 1080",
        "dist_label": "\u8ddd\u79bb", "meter_label": "\u7c73",
        "dash_label": "\u65e0\u654c\u51b2\u523a", "dash_ready": "\u5c31\u7eea",
        "dash_active": "\u53d1\u52a8\u4e2d", "dash_cool": "\u51b7\u5374\u4e2d",
        "combo_label": "\u8fde\u51fb", "pu_magnet": "\u78c1\u94c1",
        "revive_label": "\u590d\u6d3b\u5012\u8ba1\u65f6", "skip_hint": "\u6309\u4efb\u610f\u952e\u8df3\u8fc7",
        "also_try": "Also try Bililearn",
        "pu_shield": "\u62a4\u76fe", "pu_burst": "\u91d1\u5e01\u7206\u53d1",
        "shield_ready": "\u62a4\u76fe\u5df2\u88c5\u5907",
        "ev_portal_t": "\u4f20\u9001\u95e8\uff01", "ev_portal_s": "\u94bb\u8fdb\u53bb\uff0c\u5168\u662f\u91d1\u5e01",
        "ev_coin_rain_t": "\u91d1\u5e01\u96e8\uff01", "ev_coin_rain_s": "\u5f20\u5634\u63a5\u4f4f",
        "ev_low_g_t": "\u6708\u7403\u91cd\u529b\uff01", "ev_low_g_s": "\u6574\u4e2a\u4eba\u98d8\u8d77\u6765",
        "ev_high_g_t": "\u91cd\u529b\u66b4\u6da8\uff01", "ev_high_g_s": "\u5f80\u4e0b\u6389\u5427",
        "ev_turbo_t": "\u65e0\u654c\u72c2\u98d9\uff01", "ev_turbo_s": "\u514d\u8d39\u51b2\u523a\u9001\u4f60\u4e86",
        "ev_meteor_t": "\u9668\u77f3\u96e8\uff01", "ev_meteor_s": "\u5feb\u8eb2\u5f00",
        "ev_double_t": "\u91d1\u5e01\u53cc\u500d\uff01", "ev_double_s": "\u8d5a\u7ffb\u4e86",
        "ev_fever_t": "\u91d1\u5e01\u7ef4\u5ea6\uff01", "ev_fever_s": "20 \u79d2\uff0c\u968f\u4fbf\u5403\uff01",
        "ev_sec": "\u79d2",
        "w_sky_t": "\u6674\u7a7a\u4e07\u91cc", "w_sky_s": "\u5148\u70ed\u70ed\u8eab",
        "w_space_t": "\u592a\u7a7a", "w_space_s": "\u4f4e\u91cd\u529b\uff0c\u98d8\u4e00\u70b9",
        "w_jungle_t": "\u539f\u59cb\u68ee\u6797", "w_jungle_s": "\u6811\u5f88\u5bc6\uff0c\u522b\u649e\u4e0a",
        "w_dream_t": "\u68a6\u5e7b\u4e16\u754c", "w_dream_s": "\u8fd9\u91cc\u4e0d\u8bb2\u7269\u7406",
        "w_upside_t": "\u4e0a\u4e0b\u98a0\u5012", "w_upside_s": "\u808c\u8089\u8bb0\u5fc6\u5931\u6548",
        "w_coin_t": "\u91d1\u5e01\u7ef4\u5ea6", "w_coin_s": "20 \u79d2\uff0c\u968f\u4fbf\u5403\uff01",
    },
}


def emit(t: dict, lang: str) -> None:
    """按语言产出一整套界面贴图。文件名两套完全一致，只是目录不同 ——
    这样运行期换语言就是把路径里的 /ui/<lang>/ 换掉，不需要任何映射表。"""
    print(f"生成界面素材 [{lang}]：")
    save(make_title(t["title"], 3), "ui_title.png", lang)
    for key, name in (("btn_start", "start"), ("btn_quit", "quit")):
        save(make_button(t[key]), f"ui_btn_{name}.png", lang)
        save(make_button(t[key], hover=True), f"ui_btn_{name}_hover.png", lang)
        save(make_button(t[key], pressed=True), f"ui_btn_{name}_pressed.png", lang)
    save(make_label(t["hint"], 12), "ui_hint.png", lang)
    save(make_label(t["tip"], 12), "ui_tip.png", lang)
    save(make_label(t["best_label"], 12, "#FBF236"), "ui_best_label.png", lang)
    save(make_label(t["coin_label"], 12), "ui_coin_label.png", lang)
    save(make_label(t["over_title"], 26, "#F2724E", pad=6, outline=2), "ui_over_title.png", lang)
    for key, name in (("btn_retry", "retry"), ("btn_menu", "menu")):
        save(make_button(t[key]), f"ui_btn_{name}.png", lang)
        save(make_button(t[key], hover=True), f"ui_btn_{name}_hover.png", lang)
        save(make_button(t[key], pressed=True), f"ui_btn_{name}_pressed.png", lang)

    # 机哥模式的难度档位（按钮小一号，免得整行超宽）
    for tag in ("lv0", "lv1", "lv2"):
        save(make_button(t[f"btn_{tag}"], size=12), f"ui_btn_{tag}.png", lang)
        save(make_button(t[f"btn_{tag}"], size=12, hover=True), f"ui_btn_{tag}_hover.png", lang)
        save(make_button(t[f"btn_{tag}"], size=12, pressed=True), f"ui_btn_{tag}_pressed.png", lang)

    # 皮肤面板
    save(make_button(t["btn_skins"]), "ui_btn_skins.png", lang)
    save(make_button(t["btn_skins"], hover=True), "ui_btn_skins_hover.png", lang)
    save(make_button(t["btn_skins"], pressed=True), "ui_btn_skins_pressed.png", lang)
    save(make_label(t["skin_title"], 26, "#FFB0E0", pad=6, outline=2), "ui_skin_title.png", lang)
    save(make_label(t["label_aircraft"], 12, "#FBF236"), "ui_label_aircraft.png", lang)
    save(make_label(t["label_pilot"], 12, "#9FF8FF"), "ui_label_pilot.png", lang)
    save(make_label(t["label_editing"], 12), "ui_label_editing.png", lang)
    for tag in ("p1", "p2"):
        save(make_button(t[f"btn_{tag}"], size=12), f"ui_btn_{tag}.png", lang)
        save(make_button(t[f"btn_{tag}"], size=12, hover=True), f"ui_btn_{tag}_hover.png", lang)
        save(make_button(t[f"btn_{tag}"], size=12, pressed=True), f"ui_btn_{tag}_pressed.png", lang)
    save(make_button(t["btn_close"]), "ui_btn_close.png", lang)
    save(make_button(t["btn_close"], hover=True), "ui_btn_close_hover.png", lang)
    save(make_button(t["btn_close"], pressed=True), "ui_btn_close_pressed.png", lang)

    # 模式切换按钮：按钮文字本身就表明当前模式，省掉一行"当前：xxx"的标签
    for tag in ("solo", "coop", "bot"):
        save(make_button(t[f"btn_{tag}"]), f"ui_btn_{tag}.png", lang)
        save(make_button(t[f"btn_{tag}"], hover=True), f"ui_btn_{tag}_hover.png", lang)
        save(make_button(t[f"btn_{tag}"], pressed=True), f"ui_btn_{tag}_pressed.png", lang)

    # 设置面板
    save(make_button(t["btn_settings"]), "ui_btn_settings.png", lang)
    save(make_button(t["btn_settings"], hover=True), "ui_btn_settings_hover.png", lang)
    save(make_button(t["btn_settings"], pressed=True), "ui_btn_settings_pressed.png", lang)
    save(make_label(t["settings_title"], 26, "#9FF8FF", pad=6, outline=2), "ui_set_title.png", lang)
    save(make_label(t["label_language"], 12, "#FBF236"), "ui_label_language.png", lang)
    save(make_label(t["label_window"], 12, "#FBF236"), "ui_label_window.png", lang)
    save(make_label(t["label_resolution"], 12, "#FBF236"), "ui_label_resolution.png", lang)
    # 选项按钮做成"一组里选一个"，靠 modulate 表示选中（和皮肤面板的 P1/P2 一个套路）
    for key, name in (("btn_en", "lang_en"), ("btn_zh", "lang_zh"),
                      ("btn_windowed", "win_off"), ("btn_fullscreen", "win_on"),
                      ("res0", "res0"), ("res1", "res1"), ("res2", "res2")):
        save(make_button(t[key], size=13), f"ui_opt_{name}.png", lang)
        save(make_button(t[key], size=13, hover=True), f"ui_opt_{name}_hover.png", lang)
        save(make_button(t[key], size=13, pressed=True), f"ui_opt_{name}_pressed.png", lang)

    save(make_shade(), "ui_shade.png", lang)

    print(f"生成 HUD 素材 [{lang}]：")
    save(make_label(t["dist_label"], 12), "ui_dist_label.png", lang)
    save(make_label(t["meter_label"], 12), "ui_meter_label.png", lang)
    save(make_label(t["dash_label"], 12), "ui_dash_label.png", lang)
    save(make_label(t["dash_ready"], 12, "#FBF236"), "ui_dash_ready.png", lang)
    save(make_label(t["dash_active"], 12, "#FFC93C"), "ui_dash_active.png", lang)
    save(make_label(t["dash_cool"], 12, "#93A3B0"), "ui_dash_cool.png", lang)
    # 这几个原本在 gen_powerups.py 里，但它们都是**带文字**的标签，得跟着语言走
    save(make_label(t["combo_label"], 12, "#FBF236"), "ui_combo_label.png", lang)
    save(make_label(t["revive_label"], 12, "#FF9A9A"), "ui_revive_label.png", lang)
    save(make_label(t["skip_hint"], 12, "#8FA0A8"), "ui_skip_hint.png", lang)
    # 菜单标题右下角那行推广文案。黄底像素字，字号给到 28（点阵放到 4 倍）
    save(make_label(t["also_try"], 28, "#FBF236"), "ui_also_try.png", lang)
    save(make_label(t["pu_magnet"], 12, "#FF9A9A"), "ui_pu_magnet.png", lang)
    save(make_label(t["pu_shield"], 12, "#9FE8FF"), "ui_pu_shield.png", lang)
    save(make_label(t["pu_burst"], 12, "#FFF6C0"), "ui_pu_burst.png", lang)
    save(make_label(t["shield_ready"], 12, "#9FE8FF"), "ui_shield_ready.png", lang)

    # 事件横幅 / 换场横幅（原本在 gen_events.py 与 gen_worlds.py 里，
    # 但它们是带文字的，必须跟着语言出两套）
    for eid, col in {'portal': '#C9A8FF', 'coin_rain': '#FBF236', 'low_g': '#9FF8FF', 'high_g': '#FF9A6A', 'turbo': '#FFE070', 'meteor': '#FF7A5A', 'double': '#B9F06A', 'fever': '#FFFBD0'}.items():
        save(make_label(t["ev_%s_t" % eid], 26, col, pad=7, outline=2), "ev_title_%s.png" % eid, lang)
        save(make_label(t["ev_%s_s" % eid], 12, "#E4EDF5"), "ev_sub_%s.png" % eid, lang)
    save(make_label(t["ev_sec"], 12, "#FBF236"), "ev_sec_label.png", lang)
    for wid, col in {'sky': '#FBF236', 'space': '#9FF8FF', 'jungle': '#B9F06A', 'dream': '#FFB0E0', 'upside': '#FF9A6A', 'coin': '#FFFBD0'}.items():
        save(make_label(t["w_%s_t" % wid], 26, col, pad=7, outline=2), "w_title_%s.png" % wid, lang)
        save(make_label(t["w_%s_s" % wid], 12, "#E4EDF5"), "w_sub_%s.png" % wid, lang)

    # 数字和道具图标与语言无关，但为了路径规则统一，两套都放一份
    for d in range(10):
        save(make_digit(d), f"ui_digit_{d}.png", lang)


def main() -> None:
    for lang in ("en", "zh"):
        emit(STRINGS[lang], lang)
    # 跟语言无关的图（道具图标、护盾、玩家编号牌）仍留在 art/ 根目录，
    # ui_lang.gd 只改 art/ui/<lang>/ 下的东西，不会碰它们。


if __name__ == "__main__":
    main()
