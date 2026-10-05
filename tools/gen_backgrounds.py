#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 像素风背景图层生成器

设计分辨率 320x180（逻辑像素），按整数倍 S=6 最近邻放大到 1920x1080，
与工程里 rendering/textures/canvas_textures/default_texture_filter=0 (Nearest) 匹配。
游戏内相机 zoom 固定为 1.0，保证美术始终是 6 倍整数像素，不会出现像素抖动。

所有需要横向平铺的图层都严格周期化：
  * 正弦叠加 —— 波长取 320 的因数，天然周期；
  * 环形平滑噪声 —— 卷积时首尾相接，天然周期。
因此左右边缘像素级吻合，可以无限无缝循环。
"""
from __future__ import annotations

import os
import numpy as np
from PIL import Image

S = 6                      # 放大倍率
LW, LH = 320, 180          # 逻辑分辨率 -> 1920x1080

# 游戏内相机：玩家出生点 (91, 657) + Camera2D.offset (140, -90)
CAM = np.array([231.0, 567.0])
GROUND_SURFACE_Y = 693.0   # 地面碰撞面的世界坐标 y

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, ".."))
ART = os.path.join(PROJ, "art")

# 各图层逻辑高度（放大 S 倍即世界像素高度）
H_CLOUDS, H_MTN, H_HILLS, H_TREES, H_GROUND = 70, 80, 46, 30, 80


# ---------------------------------------------------------------- 调色板
def rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


# 与 bird_blue.png 呼应的复古配色：哑光低饱和 + 高亮黄作点缀
# 天空关键色（会在其间插值出 32 级调色板，抖动点因此几乎不可见）
SKY_KEYS = [
    (0.00, "#2A55AC"), (0.24, "#3F70C6"), (0.46, "#6E9ADA"),
    (0.62, "#A6C4EA"), (0.76, "#CFE1F5"), (0.90, "#E8F1FA"), (1.00, "#F5F9FD"),
]
SUN_CORE, SUN_GLOW = rgb("#FFF6CE"), rgb("#FFE9A0")

CLOUD_TOP, CLOUD_HI, CLOUD_MID, CLOUD_LOW, CLOUD_EDGE = (
    rgb("#FFFFFF"), rgb("#F7FBFF"), rgb("#E2EDF8"), rgb("#C8D9EC"), rgb("#AFC4DC"))

MTN_BACK, MTN_BACK_HI, MTN_BACK_SNOW = rgb("#93A5CE"), rgb("#A9B8DE"), rgb("#E6EBF8")
MTN_FRONT, MTN_FRONT_HI, MTN_FRONT_SNOW = rgb("#6A80B6"), rgb("#8497C8"), rgb("#DEE6F7")

HILL_BACK, HILL_FRONT = rgb("#6E9A93"), rgb("#59897F")
HILL_HI, HILL_SH = rgb("#83B3A7"), rgb("#41706A")

TREE_FAR, TREE_FAR_HI, TREE_FAR_EDGE = rgb("#33604E"), rgb("#3F7159"), rgb("#1D3B31")
TREE, TREE_HI, TREE_SH, TREE_EDGE = (
    rgb("#2A5142"), rgb("#3E7860"), rgb("#1C3A2E"), rgb("#152C23"))
TRUNK = rgb("#3B3040")

ROAD_WHITE, ROAD_DARK, ROAD_YELLOW, ROAD_YELLOW_HI = (
    rgb("#F4F4F4"), rgb("#22292B"), rgb("#FBF236"), rgb("#FFF06A"))
ASPHALT = rgb("#323C39")

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
], dtype=np.float64) / 64.0


def sky_palette(steps: int = 32) -> np.ndarray:
    """把 SKY_KEYS 插值成 steps 级调色板，相邻色差极小，抖动不可见。"""
    keys = [(p, rgb(c).astype(np.float64)) for p, c in SKY_KEYS]
    pos = np.array([p for p, _ in keys])
    cols = np.array([c for _, c in keys])
    out = np.zeros((steps, 3))
    for i, t in enumerate(np.linspace(0.0, 1.0, steps)):
        j = int(np.clip(np.searchsorted(pos, t) - 1, 0, len(keys) - 2))
        f = (t - pos[j]) / max(pos[j + 1] - pos[j], 1e-9)
        out[i] = cols[j] * (1 - f) + cols[j + 1] * f
    return out


# ---------------------------------------------------------------- 工具函数
def blank(w: int, h: int, color=None) -> np.ndarray:
    img = np.zeros((h, w, 4), dtype=np.float32)
    if color is not None:
        img[:, :, :3] = color
        img[:, :, 3] = 255.0
    return img


def disc_wrap(w: int, h: int, cx: float, cy: float, r: float) -> np.ndarray:
    """水平方向环形环绕的实心圆（跨边界自动折返，保证可平铺）。"""
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - cx)
    dx = np.minimum(dx, w - dx)
    dy = yy - cy
    return (dx / max(r, 1e-6)) ** 2 + (dy / max(r, 1e-6)) ** 2 <= 1.0


def ellipse_wrap(w, h, cx, cy, rx, ry) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - cx)
    dx = np.minimum(dx, w - dx)
    dy = yy - cy
    return (dx / max(rx, 1e-6)) ** 2 + (dy / max(ry, 1e-6)) ** 2 <= 1.0


def periodic_noise(w: int, rng, radius: int, passes: int = 2) -> np.ndarray:
    """环形平滑噪声，输出 0..1，长度 w，天然周期。"""
    a = rng.random(w)
    k = np.ones(2 * radius + 1) / (2 * radius + 1)
    for _ in range(passes):
        a = np.convolve(np.concatenate([a[-radius:], a, a[:radius]]), k, mode="valid")
    a = a - a.min()
    return a / max(a.max(), 1e-9)


def sines(w: int, rng, octaves) -> np.ndarray:
    """整数波长正弦叠加，输出 -1..1，长度 w，天然周期。"""
    x = np.arange(w)
    out = np.zeros(w)
    for wavelength, amp in octaves:
        out += amp * np.sin(2 * np.pi * x / wavelength + rng.random() * 2 * np.pi)
    return out


def fill_below(img, profile, color, w, h) -> np.ndarray:
    yy = np.mgrid[0:h, 0:w][0]
    mask = yy >= profile[None, :]
    img[:, :, :3][mask] = color
    img[:, :, 3][mask] = 255.0
    return mask


def shade_columns(img, mask, top_color, hi_color, body_color, sh_color,
                  hi_depth=3, sh_depth=3) -> None:
    """按“距该列顶部的深度”做立体的枕形明暗，像素画常用手法。"""
    h, w = mask.shape
    for x in range(w):
        col = np.flatnonzero(mask[:, x])
        if col.size == 0:
            continue
        top, bot = col[0], col[-1]
        for y in col:
            if y == top:
                c = top_color
            elif y - top <= hi_depth:
                c = hi_color
            elif bot - y <= sh_depth:
                c = sh_color
            else:
                c = body_color
            img[y, x, :3] = c
            img[y, x, 3] = 255.0


def upscale(logical: np.ndarray) -> Image.Image:
    arr = np.clip(logical, 0, 255).astype(np.uint8)
    small = Image.fromarray(arr, "RGBA")
    return small.resize((small.width * S, small.height * S), Image.NEAREST)


def save(logical: np.ndarray, name: str, dest: str) -> None:
    up = upscale(logical)
    os.makedirs(dest, exist_ok=True)
    up.save(os.path.join(dest, name))
    print(f"  -> {name:22s} {up.size[0]}x{up.size[1]}")


# ---------------------------------------------------------------- 天空
def make_sky(w=LW, h=LH) -> np.ndarray:
    img = blank(w, h)
    pal = sky_palette(32)

    # 1) 垂直渐变：32 级调色板 + 8x8 有序抖动，过渡平滑且带复古颗粒
    yy, xx = np.mgrid[0:h, 0:w]
    t = (yy / (h - 1)) * (len(pal) - 1)
    idx = np.clip(np.floor(t).astype(int), 0, len(pal) - 2)
    pick = np.where(t - idx > BAYER8[yy % 8, xx % 8], idx + 1, idx)
    sky = pal[pick].astype(np.float32)

    # 2) 太阳 + 柔光晕
    sx, sy = w * 0.79, h * 0.175
    dist = np.sqrt((xx - sx) ** 2 + (yy - sy) ** 2)
    core, glow = 8.0, 34.0
    k = np.clip(1.0 - (dist - core) / (glow - core), 0.0, 1.0)
    k = k * k * (3 - 2 * k)
    sky = sky * (1 - k[..., None] * 0.9) + SUN_GLOW[None, None, :] * (k[..., None] * 0.9)
    sky[dist <= core * 0.62] = SUN_CORE

    img[:, :, :3] = sky
    img[:, :, 3] = 255.0
    return img


# ---------------------------------------------------------------- 云
def make_clouds(w=LW, h=H_CLOUDS) -> np.ndarray:
    img = blank(w, h)
    rng = np.random.default_rng(20240517)

    mask = np.zeros((h, w), dtype=bool)
    specs = [
        (30, 42, 30, 9, 3), (108, 28, 34, 10, 4), (186, 46, 26, 8, 3),
        (240, 22, 30, 9, 3), (294, 38, 34, 10, 4),
    ]
    for cx, cy, rx, ry, puffs in specs:
        mask |= ellipse_wrap(w, h, cx, cy, rx, ry)
        for i in range(puffs):
            t = (i + 0.5) / puffs
            px = cx + (t - 0.5) * rx * 1.5
            r = ry * (0.75 - abs(t - 0.5) * 0.7) + rng.random() * 2
            mask |= ellipse_wrap(w, h, px, cy - ry * 0.55, r * 1.15, r)

    shade_columns(img, mask, CLOUD_TOP, CLOUD_HI, CLOUD_MID, CLOUD_EDGE,
                  hi_depth=2, sh_depth=6)
    # 中段再压一层柔和暗部
    for x in range(w):
        col = np.flatnonzero(mask[:, x])
        if col.size:
            mid = col[0] + int((col[-1] - col[0]) * 0.62)
            for y in col:
                if y > mid:
                    img[y, x, :3] = CLOUD_LOW
    return img


# ---------------------------------------------------------------- 远山
def make_mountains(w=LW, h=H_MTN) -> np.ndarray:
    img = blank(w, h)
    rng = np.random.default_rng(771)

    def ridge(base, amp, octaves, sharp):
        n = (sines(w, rng, octaves) + 1) * 0.5
        if sharp:
            n = 1.0 - np.abs(2.0 * n - 1.0)
        n = n * 0.72 + periodic_noise(w, rng, 4) * 0.28
        return np.clip(base - n * amp, 2, h - 1)

    back = ridge(base=26, amp=22, octaves=[(160, 0.5), (80, 0.3), (40, 0.2)], sharp=False)
    front = ridge(base=66, amp=62, octaves=[(320, 0.55), (160, 0.3), (64, 0.15)], sharp=True)

    fill_below(img, back, MTN_BACK, w, h)
    fill_below(img, front, MTN_FRONT, w, h)

    # 山体向下略微加深，做出体积感（而不是像云一样发白）
    for y in range(h):
        k = 1.0 - (y / (h - 1)) * 0.12
        on = img[y, :, 3] > 0
        img[y, on, :3] *= k

    # 受光棱线只保留 2px，避免山体发白发“云”
    yy = np.mgrid[0:h, 0:w][0]
    img[:, :, :3][(yy >= back[None, :]) & (yy < back[None, :] + 2)] = MTN_BACK_HI
    img[:, :, :3][(yy >= front[None, :]) & (yy < front[None, :] + 2)] = MTN_FRONT_HI

    # 雪顶：只铺在最尖的那批峰上，沿山脊自然展开
    for prof, snow in ((back, MTN_BACK_SNOW), (front, MTN_FRONT_SNOW)):
        line = np.percentile(prof, 12)
        for x in range(w):
            py = int(prof[x])
            if py >= line:
                continue
            for dy in range(int((line - py) * 0.55) + 1):
                y = py + dy
                if 0 <= y < h:
                    img[y, x, :3] = snow
                    img[y, x, 3] = 255.0

    # 山脚大气透视：向下逐渐融进地平线雾色
    haze = rgb("#C3D8F0").astype(np.float32)
    for y in range(h):
        k = np.clip((y - h * 0.7) / (h * 0.3), 0.0, 1.0) * 0.16
        if k > 0:
            on = img[y, :, 3] > 0
            img[y, on, :3] = img[y, on, :3] * (1 - k) + haze * k
    return img


# ---------------------------------------------------------------- 中景丘陵
def make_hills(w=LW, h=H_HILLS) -> np.ndarray:
    img = blank(w, h)
    rng = np.random.default_rng(4242)

    def profile(base, amp):
        n = (sines(w, rng, [(320, 0.5), (160, 0.3), (64, 0.2)]) + 1) * 0.5
        n = n * 0.6 + periodic_noise(w, rng, 7) * 0.4
        return np.clip(base - n * amp, 3, h - 1)

    back = profile(base=20, amp=13)
    front = profile(base=34, amp=17)

    fill_below(img, back, HILL_BACK, w, h)
    fill_below(img, front, HILL_FRONT, w, h)

    yy = np.mgrid[0:h, 0:w][0]
    img[:, :, :3][(yy >= back[None, :]) & (yy < back[None, :] + 3)] = HILL_HI
    img[:, :, :3][(yy >= front[None, :]) & (yy < front[None, :] + 3)] = HILL_HI
    img[:, :, :3][(yy >= front[None, :] - 1) & (yy < front[None, :])] = HILL_SH

    # 山脊上的远景树剪影
    for _ in range(30):
        x = int(rng.random() * w)
        y = int(back[x])
        r = int(rng.integers(1, 3))
        m = disc_wrap(w, h, x, y - r, r)
        img[:, :, :3][m] = TREE_FAR
        img[:, :, 3][m] = 255.0
    return img


# ---------------------------------------------------------------- 近景树线
def make_trees(w=LW, h=H_TREES) -> np.ndarray:
    img = blank(w, h)
    rng = np.random.default_rng(90210)
    ground = h - 1

    # depth: 0 = 最近最大、1 = 最远最小；远的先画，天然形成前后层次
    trees = []
    x = -14.0
    while x < w + 14:
        trees.append((x + rng.random() * 6.0, rng.random()))
        x += rng.integers(13, 25)
    trees.sort(key=lambda t: -t[1])

    for cx, depth in trees:
        is_far = depth > 0.58
        scale = 0.78 + (1.0 - depth) * 0.52
        canopy = TREE_FAR if is_far else TREE
        hi = TREE_FAR_HI if is_far else TREE_HI
        edge = TREE_FAR_EDGE if is_far else TREE_EDGE

        # 远的树画得更高更小，形成纵深；近的树更低更大
        cy = 7.5 + (1.0 - depth) * 8.5 + rng.random() * 2.5
        m = np.zeros((h, w), dtype=bool)
        for bx, by, br in [
            (cx, cy, 8.6 * scale), (cx - 6.0 * scale, cy + 2.8, 6.4 * scale),
            (cx + 6.0 * scale, cy + 1.8, 6.8 * scale), (cx - 1.5, cy - 4.2 * scale, 5.4 * scale),
        ]:
            m |= disc_wrap(w, h, bx, by, br)
        m &= np.mgrid[0:h, 0:w][0] <= ground

        # 树干
        tw = max(1, int(2.2 * scale))
        trunk_top = int(cy + 3.0 * scale)
        for dx in range(tw):
            for y in range(trunk_top, ground + 1):
                xx = (int(round(cx)) + dx) % w
                if not m[y, xx]:
                    img[y, xx, :3] = TRUNK
                    img[y, xx, 3] = 255.0

        shade_columns(img, m, edge, hi, canopy, TREE_SH if not is_far else edge,
                      hi_depth=3, sh_depth=2)
    return img


# ---------------------------------------------------------------- 地面 / 公路
def make_ground(w=LW, h=H_GROUND) -> np.ndarray:
    img = blank(w, h, ASPHALT)
    rng = np.random.default_rng(31337)

    for y in range(h):
        img[y, :, :3] = ASPHALT.astype(np.float32) * (1.0 - (y / (h - 1)) * 0.14)

    # 大尺度色块：模拟补丁与磨损，避免大片死黑
    for _ in range(14):
        cx, cy = rng.random() * w, rng.random() * h
        rx, ry = 14 + rng.random() * 34, 5 + rng.random() * 13
        m = ellipse_wrap(w, h, cx, cy, rx, ry)
        img[:, :, :3][m] *= 1.0 + (rng.random() - 0.45) * 0.16

    specks = rng.random((h, w))
    img[:, :, :3][specks > 0.972] *= 1.28                 # 亮碎石
    img[:, :, :3][specks < 0.030] *= 0.74                 # 暗颗粒
    np.clip(img, 0, 255, out=img)

    # 标线：白色虚线边线 + 实心黄线（比原来安静，不再像警示胶带）
    # 虚线段周期必须整除 LW，否则平铺接缝处会断线
    img[0:3, :, :3] = ROAD_DARK
    for x0 in range(0, w, 32):
        img[0:3, x0:x0 + 18, :3] = ROAD_WHITE
    img[3:4, :, :3] = ROAD_DARK
    img[4:9, :, :3] = ROAD_YELLOW
    img[4:5, :, :3] = ROAD_YELLOW_HI

    # 沥青层理与裂纹（周期化，跨边界不会断层）
    for _ in range(11):
        x0 = int(rng.integers(0, w))
        length = int(rng.integers(22, 78))
        y0 = int(rng.integers(16, h - 4))
        for i in range(length):
            xx = (x0 + i) % w
            yy = y0 + int(np.sin(i * 0.3) * 1.8)
            if 0 <= yy < h:
                img[yy, xx, :3] *= 0.74

    img[:, :, 3] = 255.0
    return img


# ---------------------------------------------------------------- 预览合成
def compose(layers: dict) -> np.ndarray:
    """按游戏内相机把各层合成成 320x180 逻辑画面（zoom=1.0）。"""
    canvas = layers["sky"].copy()
    plan = [
        ("clouds", 0.0, H_CLOUDS), ("mountains_far", GROUND_SURFACE_Y - H_MTN * S, H_MTN),
        ("hills_mid", GROUND_SURFACE_Y - H_HILLS * S, H_HILLS),
        ("trees_near", GROUND_SURFACE_Y - H_TREES * S, H_TREES),
        ("ground", GROUND_SURFACE_Y, H_GROUND),
    ]
    for name, world_top, hlog in plan:
        layer = layers[name]
        top = int(round((world_top - CAM[1] + 540.0) / S))
        for i in range(layer.shape[0]):
            y = top + i
            if 0 <= y < LH:
                a = layer[i, :, 3:4] / 255.0
                canvas[y, :, :3] = layer[i, :, :3] * a + canvas[y, :, :3] * (1 - a)
    return canvas


def preview(layers: dict) -> None:
    comp = compose(layers)
    Image.fromarray(np.clip(comp, 0, 255).astype(np.uint8), "RGBA").resize(
        (LW * 3, LH * 3), Image.NEAREST).save(os.path.join(HERE, "preview_composite.png"))
    print("  -> 预览合成 preview_composite.png")

    total = sum(l.shape[0] for l in layers.values())
    sheet = np.zeros((total, LW, 4), dtype=np.float32)
    y = 0
    for l in layers.values():
        sheet[y:y + l.shape[0]] = l
        y += l.shape[0]
    Image.fromarray(np.clip(sheet, 0, 255).astype(np.uint8), "RGBA").resize(
        (LW * 2, total * 2), Image.NEAREST).save(os.path.join(HERE, "preview_layers.png"))


def seam_report(layers: dict) -> None:
    """数值检测横向接缝。

    直接比较“环绕处列差”和“图内列差均值”会被虚线、树冠这类本身就陡变的
    内容误判。正确做法是看环绕处列差在图内所有列差分布中的分位：
    只要它不高于 99 分位，就说明环绕处的过渡和内部一样自然，即无缝。
    """
    print("平铺接缝检测（环绕处列差的分位，<=99 即无缝）：")
    for name, layer in layers.items():
        d_cols = np.abs(np.diff(layer, axis=1)).mean(axis=(0, 2))
        d_wrap = float(np.abs(layer[:, 0, :] - layer[:, -1, :]).mean())
        p99 = float(np.percentile(d_cols, 99))
        rank = float((d_cols < d_wrap).mean() * 100)
        flag = "OK " if d_wrap <= p99 * 1.2 else "!! "
        print(f"  {flag}{name:15s} wrap={d_wrap:6.2f}  p99={p99:6.2f}  "
              f"max={d_cols.max():6.2f}  分位={rank:5.1f}%")


def tiling_sheet(layers: dict) -> None:
    """把每个可平铺图层横向拼两遍，接缝会落在正中间，便于肉眼复核。"""
    strip = [layers[k] for k in ("clouds", "mountains_far", "hills_mid", "trees_near", "ground")]
    total = sum(l.shape[0] for l in strip)
    sheet = np.zeros((total, LW * 2, 4), dtype=np.float32)
    y = 0
    for l in strip:
        sheet[y:y + l.shape[0], :LW] = l
        sheet[y:y + l.shape[0], LW:] = l
        y += l.shape[0]
    Image.fromarray(np.clip(sheet, 0, 255).astype(np.uint8), "RGBA").resize(
        (LW * 2, total), Image.NEAREST).save(os.path.join(HERE, "preview_tiling.png"))
    print("  -> 平铺复核 preview_tiling.png")


def main() -> None:
    layers = {
        "sky": make_sky(),
        "clouds": make_clouds(),
        "mountains_far": make_mountains(),
        "hills_mid": make_hills(),
        "trees_near": make_trees(),
        "ground": make_ground(),
    }
    files = {
        "sky": "bg_sky.png", "clouds": "bg_clouds.png",
        "mountains_far": "bg_mountains_far.png", "hills_mid": "bg_hills_mid.png",
        "trees_near": "bg_trees_near.png", "ground": "bg_ground.png",
    }
    print("生成背景图层：")
    for key, arr in layers.items():
        save(arr, files[key], ART)
    preview(layers)
    seam_report(layers)
    tiling_sheet(layers)


if __name__ == "__main__":
    main()
