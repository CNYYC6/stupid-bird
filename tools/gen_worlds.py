#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 世界（生物群系）素材生成器

一个「世界」= 一张天空 + 3 层视差 + 一层地面 + 一套路障配色。
所有图层按 320x180 逻辑分辨率绘制，再 6 倍最近邻放大到 1920x1080；
需要横向平铺的图层全部用整数波长正弦 + 环形噪声，天然周期、无接缝。

这里生成四个世界：
    space   太空        星空 / 行星 / 星云 / 金属甲板
    jungle  原始森林    树冠逆光 / 巨型蕨叶 / 藤蔓巨木 / 苔藓地
    dream   梦幻世界    糖果云 / 浮空岛 / 棒棒糖 / 糖霜地
    coin    金币维度    纯金天光 / 金云 / 金拱门 / 金币堆 / 金砖地

第五个世界「上下颠倒」不在这里生成 —— 它是把天空世界整个垂直翻转，
由游戏里的相机 zoom.y = -1 实现，不需要额外贴图。
"""
from __future__ import annotations

import os
import numpy as np

from gen_backgrounds import (
    S, LW, LH, BAYER8, rgb, blank, disc_wrap, ellipse_wrap,
    periodic_noise, sines, fill_below, shade_columns, upscale, save,
)
from gen_backgrounds import PROJ, ART

# 各图层逻辑高度（放大 S 倍即世界像素高度）
H_FAR, H_MID, H_NEAR, H_GROUND = 70, 60, 50, 80
PILLAR_W, PILLAR_H, CAP_H = 64, 200, 14


# ================================================================ 通用画笔
def dither(img: np.ndarray, amount: float = 7.0) -> np.ndarray:
    """8x8 有序抖动：渐变上打散色带，同时带一点复古颗粒。"""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    return img + (BAYER8[yy % 8, xx % 8] - 0.5)[..., None] * amount


def vgrad(w: int, h: int, keys) -> np.ndarray:
    """垂直渐变。keys = [(位置 0..1, "#RRGGBB"), ...]，位置必须递增。"""
    pos = np.array([p for p, _ in keys], dtype=np.float64)
    cols = np.array([rgb(c) for _, c in keys], dtype=np.float64)
    yy = np.mgrid[0:h, 0:w][0]
    t = yy / max(h - 1, 1)
    out = np.zeros((h, w, 3), dtype=np.float64)
    for i in range(len(keys) - 1):
        m = (t >= pos[i]) & (t <= pos[i + 1])
        if not m.any():
            continue
        f = ((t[m] - pos[i]) / max(pos[i + 1] - pos[i], 1e-9))[:, None]
        out[m] = cols[i] * (1.0 - f) + cols[i + 1] * f
    out[t < pos[0]] = cols[0]
    out[t > pos[-1]] = cols[-1]
    return dither(out)


def add_glow(img: np.ndarray, cx: float, cy: float, r: float, color: str,
             strength: float = 0.85) -> None:
    """柔光晕（环形环绕，保证平铺安全）。"""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - cx)
    dx = np.minimum(dx, w - dx)
    d = np.sqrt(dx ** 2 + (yy - cy) ** 2)
    k = np.clip(1.0 - d / max(r, 1e-6), 0.0, 1.0) ** 2
    col = rgb(color).astype(np.float64)
    img[:, :, :3] = img[:, :, :3] * (1 - k[..., None] * strength) + col * (k[..., None] * strength)


def add_blobs(img: np.ndarray, rng, count: int, colors, rx_range, ry_range,
              soft: float = 0.45, alpha: float = 0.85) -> None:
    """一堆柔和椭圆斑块：云、星云、雾都用它。"""
    h, w = img.shape[:2]
    for _ in range(count):
        cx = rng.random() * w
        cy = rng.random() * h
        rx = rng.uniform(*rx_range)
        ry = rng.uniform(*ry_range)
        col = rgb(colors[rng.integers(len(colors))]).astype(np.float64)
        m = ellipse_wrap(w, h, cx, cy, rx, ry).astype(np.float64)
        # 再叠一圈更小的核，边缘才不是硬椭圆
        m = np.maximum(m, ellipse_wrap(w, h, cx, cy, rx * soft, ry * soft) * 0.9)
        img[:, :, :3] = img[:, :, :3] * (1 - m[..., None] * alpha) + col * (m[..., None] * alpha)


def add_stars(img: np.ndarray, rng, count: int, colors, big_chance: float = 0.05) -> None:
    """星野：绝大多数是 1 像素点，极少数带十字星芒。"""
    h, w = img.shape[:2]
    for _ in range(count):
        x = int(rng.integers(0, w))
        y = int(rng.integers(0, h))
        col = rgb(colors[rng.integers(len(colors))])
        img[y, x, :3] = col
        img[y, x, 3] = 255.0
        if rng.random() < big_chance:
            for dx, dy, k in ((1, 0, .55), (-1, 0, .55), (0, 1, .55), (0, -1, .55)):
                yy2, xx2 = y + dy, (x + dx) % w
                if 0 <= yy2 < h:
                    img[yy2, xx2, :3] = img[yy2, xx2, :3] * (1 - k) + col * k
                    img[yy2, xx2, 3] = 255.0


def ridge(w: int, rng, base: float, octaves, noise_amp: float = 0.0,
          noise_radius: int = 12) -> np.ndarray:
    """一条天然周期的高度剖面（y 值，越小越高）。"""
    prof = np.full(w, base, dtype=np.float64)
    prof += sines(w, rng, octaves) * base * 0.35
    if noise_amp:
        prof -= periodic_noise(w, rng, noise_radius) * noise_amp
    return prof


def ridged_band(w: int, h: int, rng, base_frac: float, octaves, colors,
                noise_amp: float = 0.0, hi_depth: int = 3, sh_depth: int = 3,
                spike=None) -> np.ndarray:
    """山脉 / 树冠 / 岛群：一条剖面 + 枕形明暗。colors = (顶, 高光, 体, 阴影)。"""
    img = blank(w, h)
    prof = ridge(w, rng, h * base_frac, octaves, noise_amp)
    if spike is not None:
        prof = spike(prof, w, rng)
    mask = fill_below(img, prof, rgb(colors[2]), w, h)
    shade_columns(img, mask, rgb(colors[0]), rgb(colors[1]), rgb(colors[2]),
                  rgb(colors[3]), hi_depth=hi_depth, sh_depth=sh_depth)
    return img


# ================================================================ 具体图层
def make_sky(name: str, keys, glow=None, stars=None, blobs=None, sun=None) -> np.ndarray:
    img = blank(LW, LH)
    img[:, :, :3] = vgrad(LW, LH, keys)
    img[:, :, 3] = 255.0
    rng = np.random.default_rng(abs(hash(name)) % (2 ** 31))
    if blobs:
        add_blobs(img, rng, blobs["count"], blobs["colors"], blobs["rx"],
                  blobs["ry"], alpha=blobs.get("alpha", 0.5))
    if stars:
        add_stars(img, rng, stars["count"], stars["colors"], stars.get("big", 0.05))
    if sun:
        add_glow(img, sun[0], sun[1], sun[2], sun[3], sun[4])
    return img


def make_clouds(name: str, colors, count: int, rx, ry, seed: int) -> np.ndarray:
    """云带：一簇簇蓬松的椭圆。

    注意不能把云画得太密 —— 22 团 rx 78 的椭圆铺满 320 宽之后会互相融成
    一条实心带，再叠上"底部压暗"就变成一条硬边灰色横杠。这里云团更小更疏，
    体积感改成连续渐变而不是硬切。
    """
    img = blank(LW, H_FAR)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        cx = rng.random() * LW
        cy = rng.uniform(H_FAR * 0.16, H_FAR * 0.66)
        rx_ = rng.uniform(*rx)
        ry_ = rng.uniform(*ry)
        col = rgb(colors[rng.integers(len(colors))]).astype(np.float64)
        m = ellipse_wrap(LW, H_FAR, cx, cy, rx_, ry_)
        m |= ellipse_wrap(LW, H_FAR, cx - rx_ * 0.55, cy + ry_ * 0.22, rx_ * 0.58, ry_ * 0.70)
        m |= ellipse_wrap(LW, H_FAR, cx + rx_ * 0.50, cy + ry_ * 0.18, rx_ * 0.52, ry_ * 0.74)
        m |= ellipse_wrap(LW, H_FAR, cx + rx_ * 0.05, cy - ry_ * 0.40, rx_ * 0.46, ry_ * 0.56)
        img[:, :, :3][m] = col
        img[:, :, 3][m] = 255.0

    a = img[:, :, 3] > 0
    # 底部柔和压暗：用连续渐变，避免出现一条水平硬边
    yy = np.mgrid[0:H_FAR, 0:LW][0].astype(np.float64) / max(H_FAR - 1, 1)
    k = 0.70 + 0.30 * np.clip(1.0 - yy / 0.80, 0.0, 1.0)
    img[:, :, :3][a] = np.clip(img[:, :, :3][a] * k[a][:, None], 0, 255)
    # 顶边提亮（必须同时把 alpha 补上，否则高光是透明的、等于没画）
    top = np.zeros_like(a)
    top[1:] = a[:-1] & ~a[1:]
    img[:, :, :3][top] = rgb(colors[0])
    img[:, :, 3][top] = 255.0
    return img


# ---------------------------------------------------------------- 太空
SP_SKY = [(0.00, "#04060F"), (0.35, "#0B1030"), (0.68, "#1A1546"), (1.00, "#2B1E5C")]
SP_STAR_COLORS = ["#FFFFFF", "#CFE8FF", "#FFF3C4", "#BFD0FF", "#FFD9F0"]


def make_space() -> None:
    print("太空：")
    save(make_sky(
        "space",
        SP_SKY,
        glow=("#3A2A6E", 0.3, 0.42, 0.75),
        blobs={"count": 26, "colors": ["#4A2A7A", "#7A2A6E", "#2A4A8A", "#5A3A9A"],
               "rx": (30, 90), "ry": (14, 40), "alpha": 0.30},
        stars={"count": 320, "colors": SP_STAR_COLORS, "big": 0.07},
        sun=(LW * 0.22, LH * 0.30, 16.0, "#E8D9FF", 0.55),
    ), "sp_sky.png", ART)

    img = blank(LW, H_FAR)
    add_stars(img, np.random.default_rng(101), 420, SP_STAR_COLORS, 0.06)
    save(img, "sp_stars.png", ART)

    # 行星层：两颗带环行星 + 卫星
    img = blank(LW, H_MID)
    for cx, cy, r, body, lit in ((72.0, 34.0, 20.0, "#3A2E5E", "#8A78C8"),
                                 (238.0, 26.0, 13.0, "#4A3050", "#C08A9A")):
        m = disc_wrap(LW, H_MID, cx, cy, r)
        img[:, :, :3][m] = rgb(body)
        img[:, :, 3][m] = 255.0
        # 受光面：把圆盘左上一块提亮
        yy, xx = np.mgrid[0:H_MID, 0:LW]
        dx = np.abs(xx - (cx - r * 0.35))
        dx = np.minimum(dx, LW - dx)
        lit_m = m & (((dx / (r * 0.62)) ** 2 + ((yy - (cy - r * 0.35)) / (r * 0.62)) ** 2) <= 1.0)
        img[:, :, :3][lit_m] = rgb(lit)
        # 行星环
        ring = ellipse_wrap(LW, H_MID, cx, cy, r * 1.9, r * 0.30)
        ring &= ~ellipse_wrap(LW, H_MID, cx, cy, r * 1.55, r * 0.20)
        ring &= ~m
        img[:, :, :3][ring] = rgb("#6A5A9A")
        img[:, :, 3][ring] = 255.0
    save(img, "sp_planet.png", ART)

    img = blank(LW, H_NEAR)
    add_blobs(img, np.random.default_rng(7), 22,
              ["#7A3A8A", "#2A6A9A", "#9A3A6A", "#3A3A9A"],
              (40, 110), (10, 26), alpha=0.28)
    save(img, "sp_nebula.png", ART)

    # 金属甲板：深色板 + 青色发光缝 + 铆钉
    img = blank(LW, H_GROUND)
    img[:, :, :3] = rgb("#151B26")
    img[:, :, 3] = 255.0
    img[0:3, :, :3] = rgb("#3FE0E8")
    img[3:6, :, :3] = rgb("#0F6A78")
    img[6:9, :, :3] = rgb("#26303F")
    for x in range(0, LW, 16):
        img[10:14, x:x + 2, :3] = rgb("#3A4657")
        img[H_GROUND - 18:H_GROUND - 14, (x + 8) % LW:(x + 8) % LW + 2, :3] = rgb("#3A4657")
    for y in range(16, H_GROUND, 18):
        img[y:y + 2, :, :3] = rgb("#1E2632")
    rng = np.random.default_rng(9)
    for _ in range(LW * 3):
        x = int(rng.integers(0, LW)); y = int(rng.integers(10, H_GROUND))
        img[y, x, :3] = np.clip(img[y, x, :3] * rng.uniform(0.8, 1.25), 0, 255)
    save(img, "sp_ground.png", ART)

    make_obstacle_set("sp", ("#10161F", "#2A3646", "#66788F", "#3E4C5E", "#232C39"),
                      ("#0E5A64", "#3FE0E8", "#9FF8FF"))


# ---------------------------------------------------------------- 原始森林
JU_SKY = [(0.00, "#FFF0B0"), (0.28, "#E4DA84"), (0.58, "#A8C46A"), (1.00, "#4E7A3E")]


def make_jungle() -> None:
    print("原始森林：")
    img = make_sky(
        "jungle", JU_SKY,
        glow=("#FFF6C8", 0.5, 0.14, 0.62),
        blobs={"count": 16, "colors": ["#DCE8A0", "#C2D888", "#F2E8B0"],
               "rx": (40, 100), "ry": (8, 20), "alpha": 0.35},
    )
    # 从上方斜射下来的光柱
    yy, xx = np.mgrid[0:LH, 0:LW]
    for cx, wid in ((70, 26), (150, 18), (250, 30)):
        beam = np.clip(1.0 - np.abs(((xx - cx + (yy * 0.55)) % LW) - LW / 2) / wid, 0.0, 1.0)
        beam = beam * np.clip(1.0 - yy / (LH * 1.05), 0.0, 1.0)
        img[:, :, :3] = img[:, :, :3] * (1 - beam[..., None] * 0.18) + \
            rgb("#FFFBD0") * (beam[..., None] * 0.18)
    save(img, "ju_sky.png", ART)

    save(ridged_band(LW, H_FAR, np.random.default_rng(21), 0.42,
                     [(37, 0.5), (13, 0.3), (7, 0.2)], 
                     ("#7FA8A0", "#9CC0B4", "#5E8A84", "#3E625E"),
                     noise_amp=10.0, spike=_canopy_spikes),
         "ju_canopy_far.png", ART)

    save(ridged_band(LW, H_MID, np.random.default_rng(22), 0.50,
                     [(29, 0.6), (11, 0.25)], 
                     ("#4E8A5A", "#6FB07A", "#356B44", "#22492E"),
                     noise_amp=8.0, spike=_fern_spikes),
         "ju_fern_mid.png", ART)

    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(23)
    for cx in (24.0, 118.0, 206.0, 290.0):
        wdt = rng.uniform(7.0, 13.0)
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx, H_NEAR * 0.55, wdt, H_NEAR) & 
                       (np.mgrid[0:H_NEAR, 0:LW][0] > 4)] = rgb("#3A2A22")
        img[:, :, 3][ellipse_wrap(LW, H_NEAR, cx, H_NEAR * 0.55, wdt, H_NEAR)] = 255.0
        # 树干左侧受光
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx - wdt * 0.35, H_NEAR * 0.55, wdt * 0.35, H_NEAR)] = rgb("#5A4436")
        # 藤蔓
        for k in range(3):
            vx = cx + rng.uniform(-wdt * 1.6, wdt * 1.6)
            vy = rng.uniform(2, H_NEAR * 0.7)
            img[:, :, :3][ellipse_wrap(LW, H_NEAR, vx, vy + H_NEAR * 0.25, 1.4, H_NEAR * 0.35)] = rgb("#4E7A3A")
            img[:, :, 3][ellipse_wrap(LW, H_NEAR, vx, vy + H_NEAR * 0.25, 1.4, H_NEAR * 0.35)] = 255.0
    save(img, "ju_trunks_near.png", ART)

    save(_ground_band(("#4A3A22", "#6B5A2E", "#3A2E1A", "#5E8A3A", "#8FBF5A"),
                      seed=24, tufts=True), "ju_ground.png", ART)

    make_obstacle_set("ju", ("#1E2818", "#3E4A2C", "#8A9A6A", "#5A6E3E", "#33401F"),
                      ("#3E5A22", "#7FA83C", "#C4E07A"))


def _canopy_spikes(prof, w, rng):
    """在剖面顶部加一排树冠圆包。"""
    out = prof.copy()
    for cx in range(0, w, 11):
        r = rng.uniform(5, 9)
        xs = (np.arange(int(cx - r), int(cx + r)) % w)
        depth = np.sqrt(np.maximum(r * r - (np.arange(int(cx - r), int(cx + r)) - cx) ** 2, 0))
        out[xs] = np.minimum(out[xs], prof[int(cx) % w] - depth * 0.9)
    return out


def _fern_spikes(prof, w, rng):
    """蕨叶：短而尖的锯齿。"""
    out = prof.copy()
    for cx in range(0, w, 5):
        hgt = rng.uniform(3, 11)
        out[cx % w] = prof[cx % w] - hgt
        out[(cx + 1) % w] = prof[cx % w] - hgt * 0.5
    return out


# ---------------------------------------------------------------- 梦幻世界
DR_SKY = [(0.00, "#FFD1F0"), (0.26, "#F0B4FF"), (0.52, "#C6A8FF"), (0.76, "#9BD8FF"), (1.00, "#8FF0E0")]


def make_dream() -> None:
    print("梦幻世界：")
    img = make_sky(
        "dream", DR_SKY,
        glow=("#FFFFFF", 0.5, 0.30, 0.72),
        blobs={"count": 30, "colors": ["#FFE0F8", "#E8D0FF", "#D0F0FF", "#FFD8C0"],
               "rx": (30, 85), "ry": (10, 26), "alpha": 0.34},
    )
    # 彩虹弧
    yy, xx = np.mgrid[0:LH, 0:LW]
    for i, col in enumerate(("#FF9AC0", "#FFD08A", "#FFF09A", "#A8F0A0", "#9AD8FF", "#C9A8FF")):
        r = 120.0 + i * 4.0
        d = np.sqrt((xx - LW * 0.35) ** 2 + (yy - LH * 1.25) ** 2)
        band = (np.abs(d - r) < 2.0)
        img[:, :, :3][band] = img[:, :, :3][band] * 0.35 + rgb(col) * 0.65
    add_stars(img, np.random.default_rng(31), 90,
              ["#FFFFFF", "#FFF3A0", "#FFD1F0", "#C9A8FF"], 0.30)
    save(img, "dr_sky.png", ART)

    save(make_clouds("dr", ("#FFFFFF", "#FFE8F8", "#FFD0EC"), 15, (22, 58), (8, 16), 32),
         "dr_clouds.png", ART)

    # 浮空岛：上宽下尖的倒锥
    img = blank(LW, H_MID)
    rng = np.random.default_rng(33)
    for cx, cy, rx_, cap in ((58.0, 30.0, 34.0, "#8FE07A"), (176.0, 22.0, 26.0, "#A0E8FF"),
                             (272.0, 38.0, 30.0, "#FFB0E0")):
        top = ellipse_wrap(LW, H_MID, cx, cy, rx_, 8.0)
        img[:, :, :3][top] = rgb(cap)
        img[:, :, 3][top] = 255.0
        yy, xx = np.mgrid[0:H_MID, 0:LW]
        dx = np.abs(xx - cx); dx = np.minimum(dx, LW - dx)
        cone = (yy >= cy) & (yy <= cy + 22.0) & (dx <= rx_ * (1.0 - (yy - cy) / 22.0))
        img[:, :, :3][cone] = rgb("#7A5A48")
        img[:, :, 3][cone] = 255.0
        # 挂下来的小瀑布
        fall = (dx <= 2.5) & (yy > cy + 4) & (yy < cy + 22)
        img[:, :, :3][fall] = rgb("#BFEFFF")
        img[:, :, 3][fall] = 255.0
    save(img, "dr_islands.png", ART)

    # 糖果树：棒棒糖 / 拐杖糖 / 蘑菇
    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(34)
    for x in range(6, LW, 22):
        kind = rng.integers(0, 3)
        hgt = rng.uniform(20, 34)
        y0 = int(H_NEAR - hgt)
        if kind == 0:      # 棒棒糖
            m = ellipse_wrap(LW, H_NEAR, x + 4.0, y0 + 7.0, 7.0, 7.0)
            img[:, :, :3][m] = rgb("#FF7AB8"); img[:, :, 3][m] = 255.0
            s = ellipse_wrap(LW, H_NEAR, x + 4.0, y0 + 7.0, 6.0, 6.0) & \
                (np.mgrid[0:H_NEAR, 0:LW][0] + np.mgrid[0:H_NEAR, 0:LW][1]) % 6 < 3
            img[:, :, :3][s] = rgb("#FFFFFF")
            img[:, :, :3][ellipse_wrap(LW, H_NEAR, x + 4.0, H_NEAR, 1.6, hgt)] = rgb("#F0E0D0")
            img[:, :, 3][ellipse_wrap(LW, H_NEAR, x + 4.0, H_NEAR, 1.6, hgt)] = 255.0
        elif kind == 1:    # 拐杖糖
            for k in range(int(hgt)):
                yy_ = H_NEAR - 1 - k
                xx_ = (x + int(np.sin(k * 0.35) * 3)) % LW
                img[yy_, xx_, :3] = rgb("#FF4A6A") if (k // 3) % 2 == 0 else rgb("#FFFFFF")
                img[yy_, xx_, 3] = 255.0
        else:              # 蘑菇
            m = ellipse_wrap(LW, H_NEAR, x + 4.0, y0 + 6.0, 8.0, 5.0)
            img[:, :, :3][m] = rgb("#A86AFF") if rng.random() < 0.5 else rgb("#FF9060")
            img[:, :, 3][m] = 255.0
            for dx2, dy2 in ((-4, -1), (0, -2), (3, 0)):
                img[y0 + 6 + dy2, (x + 4 + dx2) % LW, :3] = rgb("#FFFFFF")
            img[:, :, :3][ellipse_wrap(LW, H_NEAR, x + 4.0, H_NEAR, 2.4, hgt * 0.6)] = rgb("#F8F0E0")
            img[:, :, 3][ellipse_wrap(LW, H_NEAR, x + 4.0, H_NEAR, 2.4, hgt * 0.6)] = 255.0
    save(img, "dr_candy.png", ART)

    save(_ground_band(("#FFE8F4", "#FFFFFF", "#F0B8D8", "#F8A8D0", "#FFFFFF"),
                      seed=35, tufts=False, sprinkles=True), "dr_ground.png", ART)

    make_obstacle_set("dr", ("#7A2048", "#C04070", "#FFD0E8", "#E060A0", "#A02E58"),
                      ("#FFFFFF", "#FF7AB8", "#FFC0E0"))


# ---------------------------------------------------------------- 金币维度
CN_SKY = [(0.00, "#4A2E00"), (0.30, "#9A6A08"), (0.62, "#E8B020"), (1.00, "#FFF0A8")]


def make_coin_world() -> None:
    print("金币维度：")
    img = make_sky(
        "coin", CN_SKY,
        glow=("#FFFBD0", 0.5, 0.42, 0.90),
        blobs={"count": 20, "colors": ["#FFE060", "#FFC93C", "#FFF0A8"],
               "rx": (34, 96), "ry": (12, 30), "alpha": 0.34},
    )
    # 天空里印一枚巨大的淡金币
    yy, xx = np.mgrid[0:LH, 0:LW]
    big = (np.sqrt((xx - LW * 0.5) ** 2 + (yy - LH * 0.42) ** 2) < 78.0)
    inner = (np.sqrt((xx - LW * 0.5) ** 2 + (yy - LH * 0.42) ** 2) < 62.0)
    img[:, :, :3][big] = img[:, :, :3][big] * 0.55 + rgb("#FFE070") * 0.45
    img[:, :, :3][inner] = img[:, :, :3][inner] * 0.72 + rgb("#B8860B") * 0.28
    add_stars(img, np.random.default_rng(41), 180,
              ["#FFFFFF", "#FFF3A0", "#FFD54A"], 0.22)
    save(img, "cn_sky.png", ART)

    save(make_clouds("cn", ("#FFF6C8", "#FFE070", "#F5C542"), 14, (24, 60), (9, 18), 42),
         "cn_clouds.png", ART)

    # 金拱门
    img = blank(LW, H_MID)
    for x in range(4, LW, 34):
        for k in range(46):
            yy_ = H_MID - 1 - k
            for dx2 in (0, 3, 6):
                xx_ = (x + dx2) % LW
                img[yy_, xx_, :3] = rgb("#F5C542" if dx2 == 3 else "#B8860B")
                img[yy_, xx_, 3] = 255.0
        for k in range(16):
            for d in range(-9, 10):
                yy_ = H_MID - 1 - 46 - k
                xx_ = (x + 4 + d) % LW
                if abs(d) < 16 - k * 0.9:
                    img[yy_, xx_, :3] = rgb("#FFE070")
                    img[yy_, xx_, 3] = 255.0
    save(img, "cn_arches.png", ART)

    # 金币堆 + 闪光
    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(43)
    for x in range(0, LW, 6):
        pile = 4 + int(periodic_noise(LW, np.random.default_rng(44), 9)[x % LW] * 16)
        for k in range(pile):
            cx = x
            cy = H_NEAR - 1 - k * 3
            m = ellipse_wrap(LW, H_NEAR, cx + (k % 2) * 3, cy, 3.4, 2.2)
            img[:, :, :3][m] = rgb("#F5C542" if k % 3 else "#FFE070")
            img[:, :, 3][m] = 255.0
            top = ellipse_wrap(LW, H_NEAR, cx + (k % 2) * 3, cy - 0.9, 3.0, 1.2)
            img[:, :, :3][top] = rgb("#FFFBD0")
    add_stars(img, rng, 70, ["#FFFFFF", "#FFFBD0"], 0.55)
    save(img, "cn_pile.png", ART)

    save(_ground_band(("#B8860B", "#FFE070", "#8A6508", "#F5C542", "#FFF6C8"),
                      seed=45, tufts=False, bricks=True), "cn_ground.png", ART)

    make_obstacle_set("cn", ("#6A4A06", "#A87A10", "#FFE070", "#D9A62E", "#8A6508"),
                      ("#4A2E8A", "#7B4BFF", "#C9A8FF"))


# ---------------------------------------------------------------- 地面 / 路障
def _ground_band(palette, seed: int, tufts: bool = False,
                 sprinkles: bool = False, bricks: bool = False) -> np.ndarray:
    """palette = (顶部亮线, 高光带, 主体暗色, 次要色, 点缀亮色)"""
    top_line, hi, body, second, accent = palette
    img = blank(LW, H_GROUND)
    img[:, :, :3] = rgb(body)
    img[:, :, 3] = 255.0
    img[0:2, :, :3] = rgb(top_line)
    img[2:7, :, :3] = rgb(hi)
    img[7:11, :, :3] = rgb(second)
    rng = np.random.default_rng(seed)
    for y in range(12, H_GROUND, 11):
        row = (y // 11) % 2
        for x in range(-(row * 8), LW, 16):
            img[y:y + 1, x % LW:(x % LW) + 15, :3] = rgb(body)
    for _ in range(LW * 4):
        x = int(rng.integers(0, LW)); y = int(rng.integers(12, H_GROUND))
        img[y, x, :3] = np.clip(img[y, x, :3] * rng.uniform(0.78, 1.3), 0, 255)
    if tufts:
        for x in range(0, LW, 3):
            if rng.random() < 0.45:
                hgt = int(rng.integers(2, 6))
                for k in range(hgt):
                    img[2 - k if k < 2 else 0, x] = img[2 - k if k < 2 else 0, x]
                for k in range(hgt):
                    yy_ = max(1, 6 - k)
                    img[yy_, x, :3] = rgb(accent)
    if sprinkles:
        for _ in range(120):
            x = int(rng.integers(0, LW)); y = int(rng.integers(1, 12))
            img[y, x, :3] = rgb(["#FF7AB8", "#7AC8FF", "#FFE070", "#A8FF9A"][int(rng.integers(4))])
    if bricks:
        for y in range(9, H_GROUND, 7):
            img[y:y + 1, :, :3] = rgb("#8A6508")
            for x in range((y // 7 % 2) * 6, LW, 13):
                img[y:y + 6, x % LW:x % LW + 1, :3] = rgb("#8A6508")
    return img


def _band(w: int, colors) -> np.ndarray:
    """柱体某一行的横向明暗。colors = (描边, 高光, 主体, 背光)"""
    dark, lit, mid, sh = [rgb(c).astype(np.float32) for c in colors]
    row = np.zeros((w, 4), dtype=np.float32)
    row[:, 3] = 255.0
    for x in range(w):
        if x < 3 or x >= w - 3:
            c = dark
        elif x < 10:
            c = lit
        elif x < int(w * 0.72):
            c = mid
        else:
            c = sh
        row[x, :3] = c
    return row


def make_obstacle_set(tag: str, colors, cap_colors, seed: int = 7) -> None:
    """colors = (描边, 砌缝, 受光, 主体, 背光)；cap_colors = (暗, 主, 亮)"""
    dark, joint, lit, mid, sh = colors
    c_dark, c_mid, c_lit = cap_colors
    band = _band(PILLAR_W, (dark, lit, mid, sh))

    img = blank(PILLAR_W, PILLAR_H)
    img[:] = band[None, :, :]
    img[0:3, :, :3] = rgb(joint)
    img[3, :, :3] = rgb(lit)
    rng = np.random.default_rng(seed)
    for _ in range(PILLAR_W * PILLAR_H // 22):
        x = int(rng.integers(3, PILLAR_W - 3)); y = int(rng.integers(4, PILLAR_H))
        img[y, x, :3] = np.clip(img[y, x, :3] * (1.0 + (rng.random() - 0.5) * 0.22), 0, 255)
    save(img, f"obs_{tag}_pillar.png", ART)

    for name, flip in ((f"obs_{tag}_cap_top.png", False), (f"obs_{tag}_cap_hang.png", True)):
        cap = blank(PILLAR_W, CAP_H)
        cap[:] = band[None, :, :]
        for y in range(CAP_H):
            for x in range(PILLAR_W):
                c = band[x].copy()
                if 3 <= y <= CAP_H - 4:
                    c[:3] = rgb(c_lit if (x + y) % 12 < 6 else c_mid)
                cap[y, x] = c
        cap[2, :, :3] = rgb(c_dark)
        cap[CAP_H - 3, :, :3] = rgb(c_dark)
        cap[:, :3, :3] = rgb(dark)
        cap[:, -3:, :3] = rgb(dark)
        if flip:
            cap[CAP_H - 1, :] = 0
            cap[CAP_H - 1, 3:PILLAR_W - 3, :3] = rgb(dark)
            cap[CAP_H - 2, :3] = 0
            cap[CAP_H - 2, -3:] = 0
        else:
            cap[0, :] = 0
            cap[0, 3:PILLAR_W - 3, :3] = rgb(dark)
            cap[1, :3] = 0
            cap[1, -3:] = 0
        save(cap, name, ART)




def make_banners() -> None:
    """换世界时飞进来的横幅文字（中文必须烘成贴图，Godot 默认字体没有中文字形）。"""
    from gen_ui import make_label
    print("世界横幅：")
    for wid, text, sub, color in (
        ("sky", "晴空万里", "先热热身", "#FBF236"),
        ("space", "太空", "低重力，飘一点", "#9FF8FF"),
        ("jungle", "原始森林", "树很密，别撞上", "#B9F06A"),
        ("dream", "梦幻世界", "这里不讲物理", "#FFB0E0"),
        ("upside", "上下颠倒", "肌肉记忆失效", "#FF9A6A"),
        ("coin", "金币维度", "20 秒，随便吃！", "#FFFBD0"),
    ):
        save(make_label(text, 26, color, pad=7, outline=2), f"w_title_{wid}.png", ART)
        save(make_label(sub, 12, "#E4EDF5"), f"w_sub_{wid}.png", ART)


# ---------------------------------------------------------------- 第四层
def make_extras() -> None:
    """每个世界补一层「近景」，让四层视差各有各的内容，不至于两层重复用同一张图。"""
    print("近景补充：")

    # 太空：小行星带
    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(51)
    for _ in range(38):
        cx = rng.random() * LW
        cy = rng.uniform(4, H_NEAR - 4)
        r = rng.uniform(2.2, 7.5)
        m = disc_wrap(LW, H_NEAR, cx, cy, r)
        img[:, :, :3][m] = rgb("#57506E")
        img[:, :, 3][m] = 255.0
        img[:, :, :3][disc_wrap(LW, H_NEAR, cx - r * 0.32, cy - r * 0.32, r * 0.5)] = rgb("#8E88A8")
    save(img, "sp_debris.png", ART)

    # 原始森林：树冠间的雾气
    img = blank(LW, H_FAR)
    add_blobs(img, np.random.default_rng(52), 28,
              ["#C8DFA8", "#DCE9BC", "#A6CC8E"], (26, 72), (8, 20), alpha=0.34)
    add_stars(img, np.random.default_rng(53), 40, ["#FFFBD0", "#FFFFFF"], 0.25)
    save(img, "ju_haze.png", ART)

    # 梦幻：热气球 + 星星
    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(54)
    for cx, cy, col in ((40.0, 18.0, "#FF9AC0"), (150.0, 12.0, "#9AD8FF"), (262.0, 22.0, "#FFE070")):
        m = ellipse_wrap(LW, H_NEAR, cx, cy, 11.0, 13.0)
        img[:, :, :3][m] = rgb(col)
        img[:, :, 3][m] = 255.0
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx, cy - 6.0, 4.0, 7.0)] = rgb("#FFFFFF")
        # 吊篮
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx, cy + 17.0, 3.5, 3.0)] = rgb("#A87A4A")
        img[:, :, 3][ellipse_wrap(LW, H_NEAR, cx, cy + 17.0, 3.5, 3.0)] = 255.0
        for dx in (-3, 0, 3):
            img[int(cy + 13):int(cy + 15), int(cx + dx) % LW, :3] = rgb("#6A5A4A")
            img[int(cy + 13):int(cy + 15), int(cx + dx) % LW, 3] = 255.0
    add_stars(img, rng, 60, ["#FFFFFF", "#FFF3A0", "#FFD1F0"], 0.35)
    save(img, "dr_balloons.png", ART)

    # 金币维度：漂浮的宝石
    img = blank(LW, H_NEAR)
    rng = np.random.default_rng(55)
    for cx, cy, col, col2 in ((30.0, 16.0, "#7B4BFF", "#C9A8FF"), (108.0, 30.0, "#3FE0A0", "#A8FFD8"),
                              (196.0, 14.0, "#FF5A8A", "#FFB0C8"), (286.0, 26.0, "#3FA8E0", "#A8DCFF")):
        m = ellipse_wrap(LW, H_NEAR, cx, cy, 8.0, 11.0)
        img[:, :, :3][m] = rgb(col)
        img[:, :, 3][m] = 255.0
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx - 2.5, cy - 3.5, 3.0, 4.5)] = rgb(col2)
        img[:, :, :3][ellipse_wrap(LW, H_NEAR, cx, cy + 13.0, 7.0, 2.0)] = rgb("#FFE070")
        img[:, :, 3][ellipse_wrap(LW, H_NEAR, cx, cy + 13.0, 7.0, 2.0)] = 255.0
    add_stars(img, rng, 90, ["#FFFFFF", "#FFFBD0", "#FFE070"], 0.45)
    save(img, "cn_gems.png", ART)


def main() -> None:
    os.makedirs(ART, exist_ok=True)
    make_space()
    make_jungle()
    make_dream()
    make_coin_world()
    make_extras()
    make_banners()
    print("完成。")


if __name__ == "__main__":
    main()
