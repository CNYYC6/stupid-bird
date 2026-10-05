#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stupid Bird —— 8bit 音频生成器（背景音乐 + 全部音效）

全部用 numpy 从零合成，不依赖任何外部素材：
  * 脉冲波 / 三角波 / 噪声 —— 红白机音源的基本盘，占空比决定音色明暗；
  * 3 个时变共振峰滤波器   —— 合成 "WOW" 的人声，比采样更贴 8bit 的机械感；
  * 22050Hz + 4bit 量化     —— 把音色压回 8 位时代的颗粒。

所有波形都用整数周期的包络收尾，背景音乐首尾严格对齐，循环无爆音。
"""
from __future__ import annotations

import os
import wave
import numpy as np

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "stupid-bird_副本", "audio"))

SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
        "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def nf(name: str) -> float:
    """音名 -> 频率，例如 D5 / F#4；'-' 表示休止。"""
    if name == "-":
        return 0.0
    i = 2 if len(name) > 1 and name[1] == "#" else 1
    pitch, octave = name[:i], int(name[i:])
    midi = 12 * (octave + 1) + SEMI[pitch]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# ------------------------------------------------------------------ 振荡器
def _freq(f, n: int) -> np.ndarray:
    return np.full(n, float(f)) if np.isscalar(f) else np.asarray(f, dtype=float)


def pulse(f, n: int, duty: float = 0.5) -> np.ndarray:
    ph = np.cumsum(_freq(f, n)) / SR % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def triangle(f, n: int) -> np.ndarray:
    ph = np.cumsum(_freq(f, n)) / SR % 1.0
    return 4.0 * np.abs(ph - 0.5) - 1.0


def noise(n: int, rng, lp: float = 0.0, hp: float = 0.0) -> np.ndarray:
    x = rng.uniform(-1.0, 1.0, n)
    if hp > 0.0:                      # 一阶高通，做 hi-hat
        y = np.empty(n)
        prev_x = prev_y = 0.0
        for i in range(n):
            prev_y = hp * (prev_y + x[i] - prev_x)
            prev_x = x[i]
            y[i] = prev_y
        x = y
    if lp > 0.0:                      # 一阶低通，做底鼓/军鼓的闷响
        y = np.empty(n)
        acc = 0.0
        for i in range(n):
            acc += lp * (x[i] - acc)
            y[i] = acc
        x = y
    return x


def env(n: int, a: float = 0.004, d: float = 0.06, s: float = 0.75,
        r: float = 0.03) -> np.ndarray:
    e = np.ones(n)
    ai, di, ri = min(int(a * SR), n), min(int(d * SR), n), min(int(r * SR), n)
    if ai:
        e[:ai] = np.linspace(0.0, 1.0, ai)
    if di and ai + di <= n:
        e[ai:ai + di] = np.linspace(1.0, s, di)
        e[ai + di:] = s
    if ri:
        e[n - ri:] *= np.linspace(1.0, 0.0, ri)
    return e


def resonator(x: np.ndarray, track: np.ndarray, bw: float = 90.0) -> np.ndarray:
    """时变二阶共振器：给脉冲串加上共振峰，就得到了元音。"""
    n = len(x)
    r = float(np.exp(-np.pi * bw / SR))
    theta = 2.0 * np.pi * track / SR
    a1 = -2.0 * r * np.cos(theta)
    g = (1.0 - r) * np.sqrt(np.maximum(1.0 - 2.0 * r * np.cos(2.0 * theta) + r * r, 0.0))
    y = np.zeros(n)
    y1 = y2 = 0.0
    a2 = r * r
    for i in range(n):
        v = g[i] * x[i] - a1[i] * y1 - a2 * y2
        y[i] = v
        y2 = y1
        y1 = v
    return y


def crush(x: np.ndarray, bits: int = 6) -> np.ndarray:
    """位深量化，颗粒感来源。"""
    levels = float(2 ** (bits - 1))
    return np.round(np.clip(x, -1.0, 1.0) * levels) / levels


def write_wav(name: str, x: np.ndarray) -> None:
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767.0).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  -> {name:22s} {len(x)/SR:5.2f}s  {os.path.getsize(path)//1024:5d} KB")


# ------------------------------------------------------------------ 背景音乐
BPM = 128
STEP = 60.0 / BPM / 4.0          # 一个十六分音符的秒数
BARS = 16

# 和弦进行：G - Em - C - D 走两遍，后半段用 Bm 加色彩，最后停在属和弦 D 上
# 好让循环回到开头的 G，听起来是"一段清新的小loop"而不是硬切
CHORDS = ["G", "Em", "C", "D", "G", "Em", "C", "D",
          "C", "D", "Bm", "Em", "C", "D", "G", "D"]
TONES = {"G": ["G", "B", "D"], "Em": ["E", "G", "B"], "C": ["C", "E", "G"],
         "D": ["D", "F#", "A"], "Bm": ["B", "D", "F#"]}

# 主旋律（每格 16 个十六分音符）
MELODY = [
    "D5 2 B4 2 G4 4 - 2 A4 2 B4 4",
    "E5 2 D5 2 B4 4 - 4 B4 2 D5 2",
    "C5 2 E5 2 G5 4 E5 2 D5 2 C5 4",
    "D5 2 F#5 2 A5 4 F#5 2 E5 2 D5 4",
    "G5 4 D5 2 E5 2 F#5 4 G5 4",
    "E5 4 B4 2 D5 2 E5 4 - 2 B4 2",
    "C5 4 E5 4 G5 4 A5 4",
    "F#5 2 E5 2 D5 4 - 2 A4 2 B4 4",
    "C5 2 D5 2 E5 4 G5 2 E5 2 D5 4",
    "D5 2 E5 2 F#5 4 A5 2 F#5 2 E5 4",
    "D5 4 B4 4 D5 2 F#5 2 B5 4",
    "E5 2 F#5 2 G5 4 E5 4 B4 4",
    "C5 4 E5 4 G5 2 A5 2 G5 4",
    "F#5 4 A5 4 D6 4 A5 4",
    "G5 4 D5 4 B4 4 G4 4",
    "A4 2 B4 2 D5 4 F#5 4 A5 4",
]


def parse(bar: str):
    t = bar.split()
    return [(t[i], int(t[i + 1])) for i in range(0, len(t), 2)]


def make_bgm() -> np.ndarray:
    total_n = int(BARS * 16 * STEP * SR)
    delay = int(STEP * 3 * SR)                 # 主旋律的短回声
    rng = np.random.default_rng(8)
    mix = np.zeros(total_n)

    # ---- 主音（12.5% 占空比，细而亮）----
    lead = np.zeros(total_n + delay)
    pos = 0
    for bar in MELODY:
        for name, dur in parse(bar):
            n = int(dur * STEP * SR)
            if name != "-":
                seg = int(n * 0.92)
                tone = pulse(nf(name), seg, 0.125) * env(seg, 0.004, 0.05, 0.78, 0.02)
                lead[pos:pos + seg] += tone * 0.32
            pos += n
    out = lead[:total_n].copy()
    out[:delay] += lead[total_n:total_n + delay] * 0.26      # 回声绕回开头，循环无缝
    out[delay:] += lead[:total_n - delay] * 0.26
    mix += out

    # ---- 琶音（50% 占空比，铺底）----
    arp = np.zeros(total_n)
    for b in range(BARS):
        tones = TONES[CHORDS[b]]
        for i in range(16):
            t = tones[i % 3]
            octave = 4 if i < 8 else 5
            name = f"{t}{octave}"
            st = int((b * 16 + i) * STEP * SR)
            n = int(STEP * SR * 0.85)
            if st + n > total_n:
                n = total_n - st
            arp[st:st + n] += pulse(nf(name), n, 0.5) * env(n, 0.003, 0.02, 0.5, 0.01) * 0.075
    mix += arp

    # ---- 贝斯（三角波）----
    keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    for b in range(BARS):
        root = CHORDS[b][0] if CHORDS[b] != "Bm" else "B"
        idx = keys.index(root)
        fifth = keys[(idx + 7) % 12]
        pattern = [(root + "2", 4), (root + "2", 4), (fifth + "2", 4),
                   (root + "2", 2), (root + "3", 2)]
        sp = 0
        for name, dur in pattern:
            st = int((b * 16 + sp) * STEP * SR)
            n = int(dur * STEP * SR * 0.9)
            if st + n <= total_n:
                mix[st:st + n] += triangle(nf(name), n) * env(n, 0.004, 0.05, 0.7, 0.02) * 0.30
            sp += dur

    # ---- 鼓组 ----
    def kick() -> np.ndarray:
        n = int(0.10 * SR)
        f = np.linspace(130.0, 45.0, n)
        return triangle(f, n) * env(n, 0.001, 0.04, 0.35, 0.02) * 0.55

    def snare() -> np.ndarray:
        n = int(0.10 * SR)
        body = triangle(190.0, n) * 0.35
        return (noise(n, rng, lp=0.55) * 0.8 + body) * env(n, 0.001, 0.05, 0.2, 0.03) * 0.30

    def hat() -> np.ndarray:
        n = int(0.035 * SR)
        return noise(n, rng, hp=0.55) * env(n, 0.001, 0.02, 0.1, 0.01) * 0.16

    k, s, h = kick(), snare(), hat()
    for b in range(BARS):
        for step, buf in ((0, k), (4, s), (8, k), (12, s), (14, s)):
            st = int((b * 16 + step) * STEP * SR)
            if st + len(buf) <= total_n:
                mix[st:st + len(buf)] += buf
        for step in range(0, 16, 2):
            st = int((b * 16 + step) * STEP * SR)
            if st + len(h) <= total_n:
                mix[st:st + len(h)] += h

    mix = crush(mix / max(np.abs(mix).max(), 1e-9) * 0.86, 6)
    # 去直流
    mix -= mix.mean()
    return mix


# ------------------------------------------------------------------ 音效
def sfx_coin() -> np.ndarray:
    """三个上行方波短音，明亮清脆。"""
    notes = [(1318.5, 0.035), (1568.0, 0.035), (1975.5, 0.16)]
    total = sum(int(d * SR) for _, d in notes) + int(0.05 * SR)
    buf = np.zeros(total)
    pos = 0
    for f, d in notes:
        n = int(d * SR)
        buf[pos:pos + n] += pulse(f, n, 0.25) * env(n, 0.001, 0.02, 0.85, 0.01) * 0.55
        pos += n
    return crush(buf, 6) * 0.9


def sfx_flap() -> np.ndarray:
    """滤过的噪声做一个上扬的风声，再来一点低频闷响。"""
    n = int(0.20 * SR)
    rng = np.random.default_rng(11)
    w = noise(n, rng, lp=0.22)
    t = np.linspace(0.0, 1.0, n)
    body = triangle(np.linspace(220.0, 520.0, n), n) * 0.25
    shaped = (w * 0.9 + body) * env(n, 0.012, 0.09, 0.35, 0.07)
    shaped *= 0.4 + 0.6 * np.sin(np.pi * t)         # 中间鼓一点
    return crush(shaped, 6) * 0.8


def sfx_hit() -> np.ndarray:
    """撞毁：噪声爆裂 + 大幅下滑的方波 + 少量失真。"""
    n = int(0.55 * SR)
    rng = np.random.default_rng(23)
    nz = noise(n, rng, lp=0.4) * env(n, 0.001, 0.12, 0.25, 0.3)
    drop = pulse(np.linspace(420.0, 55.0, n), n, 0.5) * env(n, 0.001, 0.1, 0.3, 0.35)
    x = nz * 0.7 + drop * 0.6
    x = np.tanh(x * 2.6) * 0.8                       # 轻微过载
    return crush(x, 5) * 0.95


def sfx_ui() -> np.ndarray:
    """界面点击：两个短促的方波。"""
    a = int(0.045 * SR)
    b = int(0.09 * SR)
    buf = np.zeros(a + b)
    buf[:a] += pulse(784.0, a, 0.5) * env(a, 0.002, 0.02, 0.7, 0.01) * 0.4
    buf[a:] += pulse(1046.5, b, 0.5) * env(b, 0.002, 0.03, 0.6, 0.02) * 0.4
    return crush(buf, 6) * 0.75


def sfx_wow(seed: int = 5) -> np.ndarray:
    """合成一声夸张的 "WOW"。

    用脉冲串当声门源，三个时变共振峰从 /w/ 滑到 /a/ 再收到 /ʊ/，
    音高先扬后抑并带颤音 —— 这是卡通式"哇哦"的做法，比采样更贴 8bit。
    """
    dur = 1.05
    n = int(dur * SR)
    t = np.arange(n) / SR

    base = np.interp(t, [0.0, 0.10, 0.30, 0.70, dur], [150.0, 250.0, 240.0, 145.0, 105.0])
    f0 = base * (1.0 + 0.022 * np.sin(2.0 * np.pi * 6.5 * t))
    src = pulse(f0, n, 0.32)

    keys = [0.0, 0.09, 0.30, 0.60, dur]
    f1 = np.interp(t, keys, [300.0, 520.0, 790.0, 540.0, 430.0])
    f2 = np.interp(t, keys, [610.0, 900.0, 1160.0, 1010.0, 900.0])
    f3 = np.interp(t, keys, [2200.0, 2400.0, 2620.0, 2460.0, 2360.0])

    voice = (resonator(src, f1, 85.0)
             + 0.55 * resonator(src, f2, 105.0)
             + 0.22 * resonator(src, f3, 140.0))
    voice /= max(np.abs(voice).max(), 1e-9)
    voice *= env(n, 0.02, 0.12, 0.95, 0.18)
    voice = np.tanh(voice * 1.9) * 0.85
    return crush(voice, 5) * 0.95


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("生成 8bit 音频：")
    write_wav("bgm_day.wav", make_bgm())
    write_wav("sfx_coin.wav", sfx_coin())
    write_wav("sfx_flap.wav", sfx_flap())
    write_wav("sfx_hit.wav", sfx_hit())
    write_wav("sfx_ui.wav", sfx_ui())
    write_wav("sfx_wow.wav", sfx_wow())


if __name__ == "__main__":
    main()
