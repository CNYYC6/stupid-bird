# 素材生成脚本

本项目的**全部**美术与音频都由这里的脚本生成，仓库中不含任何第三方素材。

## 依赖

```bash
pip install numpy pillow
```

## 用法

在仓库根目录执行：

```bash
python tools/gen_backgrounds.py   # 6 张背景图层 -> art/bg_*.png
python tools/gen_ui.py            # 标题/按钮/提示/HUD 数字 -> art/ui_*.png
python tools/gen_gameplay.py      # 路障与金币 -> art/obs_*.png, art/coin_*.png
python tools/gen_audio.py         # BGM 与音效 -> audio/*.wav
```

每个脚本都会直接覆盖 `art/` 和 `audio/` 下的产物，改完参数重跑即可，不需要手绘。

## 设计分辨率

所有贴图按 **320×180 逻辑像素**绘制，再按整数倍（6×）最近邻放大到 1920×1080。
配合 `project.godot` 里的 `default_texture_filter=0`（Nearest），像素在屏幕上永远是整齐的方块。

## 几个关键做法

**严格周期化。** 需要横向平铺的图层（云、山、丘陵、树线、地面）用「整数波长正弦叠加 + 环形卷积噪声」生成，数学上天然周期。`gen_backgrounds.py` 里还带**接缝自动检测**：比较环绕处的列差在图内所有列差分布中的分位，只要不是离群值就算无缝。

**有序抖动渐变。** 天空的渐变先在关键色之间插值出 32 级调色板，再用 8×8 Bayer 矩阵抖动。相邻色差极小，所以抖动点几乎不可见，但过渡仍然是硬边像素而不是平滑插值。

**中文点阵。** Godot 默认字体（Open Sans）不含中文字形。这里用系统黑体把字串渲染成 12/16px 位图，再做阈值二值化——笔画被「压」成硬边像素，和背景是同一套颗粒。
字体按 `CJK_CANDIDATES` 列表依次探测（macOS / Linux / Windows 各有覆盖），找不到会明确报错。

**人声合成。** `sfx_wow` 不用采样：脉冲串当声门源，过三个时变二阶共振峰滤波器，元音从 /w/ 滑到 /a/ 再收到 /ʊ/，音高先扬后抑并加 6.5Hz 颤音。

**位深量化。** 所有音频最后都做 5~6 bit 量化，这是 8bit 颗粒感的来源。
