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
OUT = os.path.abspath(os.path.join(HERE, "..", "audio"))

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
# ================================================================== 背景音乐
# 每个世界一段独立 BGM，全部 8 小节、整数十六分音符，首尾严格对齐，循环无爆音。
# 风格差异靠这四样：BPM / 和弦进行 / 主旋律 / 音色（脉冲占空比 + 鼓组轻重）。

TONES = {"G": ["G", "B", "D"], "Em": ["E", "G", "B"], "C": ["C", "E", "G"],
         "D": ["D", "F#", "A"], "Bm": ["B", "D", "F#"],
         "Am": ["A", "C", "E"], "F": ["F", "A", "C"], "E": ["E", "G#", "B"],
         "Cm": ["C", "D#", "G"], "Gm": ["G", "A#", "D"], "A#": ["A#", "D", "F"],
         "Dm": ["D", "F", "A"], "Fm": ["F", "G#", "C"], "Cmaj7": ["C", "E", "G", "B"],
         "Fmaj7": ["F", "A", "C", "E"], "Am7": ["A", "C", "E", "G"]}

# 晴空：原来那条清新的 G-Em-C-D 走两遍
SKY_MELODY = [
    "D5 2 B4 2 G4 4 - 2 A4 2 B4 4",
    "E5 2 D5 2 B4 4 - 4 B4 2 D5 2",
    "C5 2 E5 2 G5 4 E5 2 D5 2 C5 4",
    "D5 2 F#5 2 A5 4 F#5 2 E5 2 D5 4",
    "G5 4 D5 2 E5 2 F#5 4 G5 4",
    "E5 4 B4 2 D5 2 E5 4 - 2 B4 2",
    "C5 4 E5 4 G5 4 A5 4",
    "F#5 2 E5 2 D5 4 - 2 A4 2 B4 4",
]

WORLDS = {
    # 太空：慢、空、小调，几乎没有鼓，回声拉很长
    "space": dict(
        bpm=84, bars=8, crush_bits=6,
        chords=["Am", "F", "Cmaj7", "G", "Am", "F", "Dm", "E"],
        melody=[
            "A4 8 - 4 C5 4", "F4 8 - 4 A4 4", "C5 4 E5 4 G5 8",
            "G4 8 B4 4 D5 4", "A4 8 - 4 E5 4", "F4 8 A4 4 C5 4",
            "D5 4 F5 4 A5 8", "E5 8 - 8",
        ],
        lead_duty=0.25, lead_gain=0.30, echo=0.42, echo_step=6,
        arp_duty=0.5, arp_gain=0.05, arp_octave=5,
        bass_gain=0.26, kick=0, snare=0, hat=0, hat_gain=0.0,
    ),
    # 原始森林：中速五声音阶，重手鼓，三角波为主
    "jungle": dict(
        bpm=112, bars=8, crush_bits=5,
        chords=["Am", "Am", "G", "G", "F", "F", "E", "E"],
        melody=[
            "A4 4 C5 4 D5 4 E5 4", "E5 4 D5 4 C5 4 A4 4",
            "G4 4 A4 4 C5 4 D5 4", "D5 4 C5 4 A4 4 G4 4",
            "F4 4 A4 4 C5 4 D5 4", "D5 4 C5 4 A4 8",
            "E5 4 D5 4 B4 4 G#4 4", "A4 8 - 8",
        ],
        lead_duty=0.125, lead_gain=0.30, echo=0.20, echo_step=3,
        arp_duty=0.5, arp_gain=0.06, arp_octave=4,
        bass_gain=0.34, kick=1, snare=1, hat=1, hat_gain=0.12, tom=1,
    ),
    # 梦幻世界：快、大调七和弦、钟琴音色，鼓很轻
    "dream": dict(
        bpm=140, bars=8, crush_bits=6,
        chords=["Cmaj7", "Am7", "Fmaj7", "G", "Cmaj7", "Am7", "Fmaj7", "G"],
        melody=[
            "C5 2 E5 2 G5 2 E5 2 C5 4 B4 4", "A4 2 C5 2 E5 2 C5 2 A4 8",
            "F4 2 A4 2 C5 2 A4 2 F4 4 E5 4", "G4 2 B4 2 D5 2 B4 2 G4 8",
            "C5 2 E5 2 G5 2 C6 2 G5 4 E5 4", "A4 2 C5 2 E5 2 A5 2 E5 8",
            "F5 2 E5 2 C5 2 A4 2 F4 4 G4 4", "G5 4 D5 4 B4 4 G4 4",
        ],
        lead_duty=0.5, lead_gain=0.26, echo=0.30, echo_step=3,
        arp_duty=0.25, arp_gain=0.07, arp_octave=6,
        bass_gain=0.24, kick=1, snare=0, hat=1, hat_gain=0.08,
    ),
    # 上下颠倒：把晴空的主旋律做音程倒置，和弦也跟着反着走 —— 听着就是"翻过来"的
    "upside": dict(
        bpm=120, bars=8, crush_bits=5,
        chords=["D", "Bm", "G", "Em", "D", "Bm", "C", "D"],
        melody=[
            "G4 2 B4 2 D5 4 - 2 A4 2 G4 4", "C5 2 D5 2 G5 4 - 4 G5 2 D5 2",
            "E5 2 C5 2 G4 4 B4 2 D5 2 E5 4", "D5 2 A4 2 F#4 4 A4 2 C5 2 D5 4",
            "D5 4 G4 2 A4 2 B4 4 D5 4", "C5 4 G4 2 B4 2 C5 4 - 2 G4 2",
            "E5 4 C5 4 G4 4 F#4 4", "B4 2 C5 2 D5 4 - 2 F#4 2 G4 4",
        ],
        lead_duty=0.25, lead_gain=0.30, echo=0.34, echo_step=3,
        arp_duty=0.5, arp_gain=0.06, arp_octave=4,
        bass_gain=0.30, kick=1, snare=1, hat=1, hat_gain=0.14,
    ),
    # 金币维度：快、全是大调琶音、鼓最密 —— 听起来就像在数钱
    "coin": dict(
        bpm=160, bars=8, crush_bits=6,
        chords=["C", "C", "F", "G", "C", "Am", "F", "G"],
        melody=[
            "C5 1 E5 1 G5 1 C6 1 G5 2 E5 2 C5 4", "C5 1 E5 1 G5 1 C6 1 C6 4 G5 4",
            "F4 1 A4 1 C5 1 F5 1 C5 2 A4 2 F4 4", "G4 1 B4 1 D5 1 G5 1 D5 2 B4 2 G4 4",
            "C5 1 E5 1 G5 1 C6 1 E6 2 C6 2 G5 4", "A4 1 C5 1 E5 1 A5 1 E5 2 C5 2 A4 4",
            "F5 2 E5 2 C5 2 A4 2 F4 4 C5 4", "G5 2 D5 2 B4 2 G4 2 C5 8",
        ],
        lead_duty=0.125, lead_gain=0.28, echo=0.22, echo_step=2,
        arp_duty=0.25, arp_gain=0.09, arp_octave=6,
        bass_gain=0.28, kick=1, snare=1, hat=1, hat_gain=0.16,
    ),
}
# 晴空沿用原来的参数
WORLDS["sky"] = dict(
    bpm=128, bars=8, crush_bits=6,
    chords=["G", "Em", "C", "D", "G", "Em", "C", "D"],
    melody=SKY_MELODY,
    lead_duty=0.125, lead_gain=0.32, echo=0.26, echo_step=3,
    arp_duty=0.5, arp_gain=0.075, arp_octave=4,
    bass_gain=0.30, kick=1, snare=1, hat=1, hat_gain=0.16,
)

KEYS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def parse(bar: str):
    t = bar.split()
    return [(t[i], int(t[i + 1])) for i in range(0, len(t), 2)]


def make_bgm(style: dict) -> np.ndarray:
    """按风格合成一段可无缝循环的 8 小节 chiptune。"""
    bpm: int = style["bpm"]
    bars: int = style["bars"]
    step: float = 60.0 / bpm / 4.0
    chords: list = style["chords"]
    total_n: int = int(bars * 16 * step * SR)
    echo_n: int = int(step * style["echo_step"] * SR)
    rng = np.random.default_rng(bpm)
    mix = np.zeros(total_n)

    # ---- 主音 ----
    lead = np.zeros(total_n + echo_n)
    pos = 0
    for bar in style["melody"]:
        for name, dur in parse(bar):
            n = int(dur * step * SR)
            if name != "-":
                seg = int(n * 0.92)
                tone = pulse(nf(name), seg, style["lead_duty"]) * env(seg, 0.004, 0.05, 0.78, 0.02)
                lead[pos:pos + seg] += tone * style["lead_gain"]
            pos += n
    out = lead[:total_n].copy()
    # 回声绕回开头，循环才接得上
    out[:echo_n] += lead[total_n:total_n + echo_n] * style["echo"]
    out[echo_n:] += lead[:total_n - echo_n] * style["echo"]
    mix += out

    # ---- 琶音铺底 ----
    arp = np.zeros(total_n)
    for b in range(bars):
        tones = TONES.get(chords[b], TONES["C"])
        for i in range(16):
            t = tones[i % len(tones)]
            name = f"{t}{style['arp_octave'] if i < 8 else style['arp_octave'] + 1}"
            st = int((b * 16 + i) * step * SR)
            n = int(step * SR * 0.85)
            if st + n > total_n:
                n = total_n - st
            arp[st:st + n] += pulse(nf(name), n, style["arp_duty"]) \
                * env(n, 0.003, 0.02, 0.5, 0.01) * style["arp_gain"]
    mix += arp

    # ---- 贝斯 ----
    for b in range(bars):
        root = chords[b][:2] if chords[b][1:2] in ("#", "m") else chords[b][0]
        if chords[b].endswith("m") or chords[b].endswith("7"):
            root = chords[b][0] + ("#" if chords[b][1:2] == "#" else "")
        idx = KEYS.index(root) if root in KEYS else 0
        fifth = KEYS[(idx + 7) % 12]
        pattern = [(root + "2", 4), (root + "2", 4), (fifth + "2", 4),
                   (root + "2", 2), (root + "3", 2)]
        sp = 0
        for name, dur in pattern:
            st = int((b * 16 + sp) * step * SR)
            n = int(dur * step * SR * 0.9)
            if st + n <= total_n:
                mix[st:st + n] += triangle(nf(name), n) \
                    * env(n, 0.004, 0.05, 0.7, 0.02) * style["bass_gain"]
            sp += dur

    # ---- 鼓组 ----
    def kick() -> np.ndarray:
        n = int(0.10 * SR)
        return triangle(np.linspace(130.0, 45.0, n), n) * env(n, 0.001, 0.04, 0.35, 0.02) * 0.55

    def snare() -> np.ndarray:
        n = int(0.10 * SR)
        body = triangle(190.0, n) * 0.35
        return (noise(n, rng, lp=0.55) * 0.8 + body) * env(n, 0.001, 0.05, 0.2, 0.03) * 0.30

    def hat(gain: float) -> np.ndarray:
        n = int(0.035 * SR)
        return noise(n, rng, hp=0.55) * env(n, 0.001, 0.02, 0.1, 0.01) * gain

    def tom() -> np.ndarray:
        n = int(0.16 * SR)
        return triangle(np.linspace(200.0, 90.0, n), n) * env(n, 0.002, 0.07, 0.3, 0.06) * 0.34

    k, s = kick(), snare()
    h = hat(style["hat_gain"])
    tm = tom()
    for b in range(bars):
        if style["kick"]:
            for step_i in (0, 8):
                st = int((b * 16 + step_i) * step * SR)
                if st + len(k) <= total_n:
                    mix[st:st + len(k)] += k
        if style["snare"]:
            for step_i in (4, 12):
                st = int((b * 16 + step_i) * step * SR)
                if st + len(s) <= total_n:
                    mix[st:st + len(s)] += s
        if style.get("tom"):
            for step_i in (7, 15):
                st = int((b * 16 + step_i) * step * SR)
                if st + len(tm) <= total_n:
                    mix[st:st + len(tm)] += tm
        if style["hat_gain"] > 0.0:
            for step_i in range(0, 16, 2):
                st = int((b * 16 + step_i) * step * SR)
                if st + len(h) <= total_n:
                    mix[st:st + len(h)] += h

    mix = crush(mix / max(np.abs(mix).max(), 1e-9) * 0.86, style["crush_bits"])
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


def sfx_dash() -> np.ndarray:
    """无敌冲刺：一路向上扫的方波 + 一层风声。

    音高用 geomspace 做等比上扫（听感上"加速"才是线性的），
    再叠一个中间鼓起来的风噪，做出"窜出去"的推力感。
    """
    n = int(0.42 * SR)
    rng = np.random.default_rng(31)
    t = np.linspace(0.0, 1.0, n)
    sweep = pulse(np.geomspace(210.0, 1720.0, n), n, 0.35)
    body = sweep * env(n, 0.006, 0.10, 0.55, 0.16)
    wind = noise(n, rng, lp=0.30) * env(n, 0.02, 0.14, 0.40, 0.20)
    x = (body * 0.75 + wind * 0.55) * (0.45 + 0.55 * np.sin(np.pi * t))
    return crush(np.tanh(x * 1.8) * 0.85, 5) * 0.9




def loopify(x: np.ndarray, fade: int) -> np.ndarray:
    """把尾巴交叉淡入到开头，做成无缝循环。

    纯噪声的引擎声没法靠"整数周期"做到无缝（噪声没有周期），
    所以老老实实做一次交叉淡化：尾部 fade 个采样和头部 fade 个采样按权重混合。
    """
    if fade <= 0 or len(x) <= fade * 2:
        return x
    head = x[:fade].copy()
    tail = x[-fade:].copy()
    t = np.linspace(0.0, 1.0, fade)
    x = x[:-fade]
    x[:fade] = tail * (1.0 - t) + head * t
    return x


# ------------------------------------------------------------------ 阵亡
def sfx_death() -> np.ndarray:
    """阵亡：一段往下掉的方波琶音 + 噪声爆裂，比 sfx_hit 更"结束"。"""
    notes = [(523.25, 0.10), (415.30, 0.10), (329.63, 0.12), (246.94, 0.14), (164.81, 0.30)]
    total = sum(int(d * SR) for _, d in notes) + int(0.08 * SR)
    buf = np.zeros(total)
    pos = 0
    for f, d in notes:
        n = int(d * SR)
        buf[pos:pos + n] += pulse(f, n, 0.5) * env(n, 0.004, 0.05, 0.7, 0.03) * 0.45
        pos += n
    rng = np.random.default_rng(77)
    nz = noise(total, rng, lp=0.35) * env(total, 0.002, 0.18, 0.25, 0.30) * 0.30
    x = np.tanh((buf + nz) * 1.7) * 0.8
    return crush(x, 5) * 0.95


# ------------------------------------------------------------------ 飞行音效
def engine(kind: str, dur: float = 0.62) -> np.ndarray:
    """每种飞行器一个循环的飞行声。

    全部刻意做得"闷"一点：这是**长时间循环播放**的背景层，
    音量再高一点就会把金币音和 BGM 盖掉，所以这里峰值都压得比较低，
    真正的音量由 audio.gd 里的 ENGINE_DB（-22 dB）控制。
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(abs(hash(kind)) % (2 ** 31))
    fade = int(0.045 * SR)

    if kind == "classic":
        # 轻柔的风：低通噪声 + 一点点低频脉动
        x = noise(n, rng, lp=0.16) * 0.55
        x += triangle(72.0, n) * 0.18 * (0.7 + 0.3 * np.sin(2 * np.pi * 3.0 * t))
    elif kind == "penguin":
        # 摇摆：低频方波 + 慢速颤音，像一摇一摆地走
        x = pulse(96.0 * (1.0 + 0.06 * np.sin(2 * np.pi * 4.0 * t)), n, 0.5) * 0.30
        x += noise(n, rng, lp=0.10) * 0.22
    elif kind == "rocket":
        # 喷气：宽噪声 + 低频轰鸣
        x = noise(n, rng, lp=0.45) * 0.50
        x += triangle(58.0, n) * 0.30
        x *= 0.85 + 0.15 * np.sin(2 * np.pi * 9.0 * t)
    elif kind == "bat":
        # 尖啸：高频颤音，音量刻意压最低（最刺耳）
        x = pulse(880.0 * (1.0 + 0.10 * np.sin(2 * np.pi * 7.0 * t)), n, 0.25) * 0.16
        x += noise(n, rng, hp=0.5) * 0.10
    elif kind == "paper":
        # 纸的沙沙声：高通噪声 + 轻微抖动
        x = noise(n, rng, hp=0.28) * 0.30
        x *= 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 5.5 * t))
    else:  # ufo
        # 电子嗡鸣：两个失谐方波 + 慢速颤音
        x = pulse(150.0, n, 0.5) * 0.22
        x += pulse(150.0 * 1.013, n, 0.5) * 0.22
        x *= 0.75 + 0.25 * np.sin(2 * np.pi * 6.0 * t)

    x = loopify(x, fade)
    x /= max(np.abs(x).max(), 1e-9)
    return crush(x * 0.62, 6)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("生成 8bit 音频：")
    for wid, style in WORLDS.items():
        write_wav(f"bgm_{wid}.wav", make_bgm(style))
    write_wav("sfx_coin.wav", sfx_coin())
    write_wav("sfx_flap.wav", sfx_flap())
    write_wav("sfx_hit.wav", sfx_hit())
    write_wav("sfx_ui.wav", sfx_ui())
    write_wav("sfx_wow.wav", sfx_wow())
    write_wav("sfx_dash.wav", sfx_dash())
    write_wav("sfx_death.wav", sfx_death())
    for kind in ("classic", "penguin", "rocket", "bat", "paper", "ufo"):
        write_wav(f"engine_{kind}.wav", engine(kind))


if __name__ == "__main__":
    main()
