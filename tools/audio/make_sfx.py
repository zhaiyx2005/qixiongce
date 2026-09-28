# -*- coding: utf-8 -*-
"""《七雄策》游戏音效合成器（纯程序合成）。

统一音色语言：木质（按钮 / 落牌）、金属（编钟 / 锣）、皮膜（鼓）、气声（沙沙 / 呼啸）。
全部为短音效，输出 **WAV PCM16 单声道** —— 极短音频用 Vorbis 编码会有前后静音与
预回声伪影，WAV 无压缩、体积极小（每个 < 60KB），是短音效的正确选择。

输出目录 assets/sfx/
"""
import os
import sys

import numpy as np
import soundfile as sf

SR = 44100
OUT_DIR = r"E:/goodot_work/七雄策/assets/sfx"


def f_of(name: str) -> float:
    letter, octave = name[:-1], int(name[-1])
    rel = {"D": -7, "E": -5, "F#": -3, "A": 0, "B": 2}[letter]
    return 440.0 * 2.0 ** ((rel + (octave - 4) * 12) / 12.0)


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def _env_exp(n: int, rate: float, attack: float = 900.0) -> np.ndarray:
    """起音极快 + 指数衰减的包络。"""
    t = np.arange(n) / SR
    return np.minimum(1.0, t * attack) * np.exp(-t * rate)


def _lp(x: np.ndarray, k: int = 1) -> np.ndarray:
    """一阶低通，k 越大越闷。"""
    for _ in range(k):
        x = np.convolve(x, [0.5, 0.5], mode="same")
    return x


def _hp(x: np.ndarray, k: int = 1) -> np.ndarray:
    """简易高通：原信号减低通。"""
    return x - _lp(x, k)


# ---------------- 木质：按钮、落牌 ----------------

def wood(f: float, dur: float, rate: float, amp: float = 1.0, noisy: float = 0.10) -> np.ndarray:
    """木质敲击：两三个谐波的快速衰减 + 一点击打噪声。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = (np.sin(2 * np.pi * f * t)
           + 0.42 * np.sin(2 * np.pi * 2.0 * f * t)
           + 0.18 * np.sin(2 * np.pi * 3.4 * f * t))
    out += noisy * _lp(_rng(int(f)).uniform(-1, 1, n), 2)
    return amp * _env_exp(n, rate) * out


def click(amp: float = 0.55) -> np.ndarray:
    """按钮点击：干脆、短。"""
    return wood(f_of("D6"), 0.085, 62.0, amp, noisy=0.06)


def hover(amp: float = 0.18) -> np.ndarray:
    """悬停：更轻更高，只在鼠标经过时轻响。"""
    return wood(f_of("A6"), 0.05, 95.0, amp, noisy=0.03)


def card_place(amp: float = 0.85) -> np.ndarray:
    """出牌落场：木牌拍在桌上的「啪」，带一点低频胸腔感。"""
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    body = wood(f_of("A4"), 0.26, 30.0, 0.55, noisy=0.16)
    thump = np.sin(2 * np.pi * 118.0 * t) * np.exp(-t * 26.0) * 0.5
    return amp * (body + thump)


def card_draw(amp: float = 0.5) -> np.ndarray:
    """抽牌：纸牌从牌堆滑出的沙沙声（带通噪声 + 略微上扬）。"""
    n = int(0.24 * SR)
    noise = _hp(_lp(_rng(7).uniform(-1, 1, n), 1), 1)
    t = np.arange(n) / SR
    env = np.exp(-((t - 0.09) ** 2) / (2 * 0.055 ** 2))
    return amp * noise * env


# ---------------- 金属：编钟、锣 ----------------

def bell(f: float, dur: float, amp: float = 1.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    ratios = [1.0, 2.0, 2.76, 3.76, 5.40, 6.85]
    gains = [1.0, 0.50, 0.42, 0.26, 0.15, 0.08]
    out = np.zeros(n)
    for r, g in zip(ratios, gains):
        if f * r > SR * 0.45:
            break
        out += g * np.exp(-(1.1 + 0.75 * r) * t) * np.sin(2 * np.pi * f * r * t)
    out += 0.08 * np.exp(-t * 120.0) * _rng(int(f) % 9973).uniform(-1, 1, n)
    return amp * np.minimum(1.0, t * 600.0) * out


def tactic(amp: float = 0.62) -> np.ndarray:
    """计策释放：编钟短鸣 + 一道上扬的气声，表达「谋略出手」。"""
    n = int(1.05 * SR)
    t = np.arange(n) / SR
    metal = bell(f_of("D5"), 1.05, 0.9)
    sweep_f = 320.0 + 760.0 * (t / t[-1]) ** 1.4
    phase = 2 * np.pi * np.cumsum(sweep_f) / SR
    sweep = np.sin(phase) * np.exp(-t * 3.0) * 0.30
    air = _hp(_rng(21).uniform(-1, 1, n), 2) * np.exp(-t * 4.5) * 0.16
    return amp * (metal + sweep + air)


def gong(dur: float = 2.2, amp: float = 0.8) -> np.ndarray:
    """大锣：低、散、余音长。用于「将军」等高光时刻。

    `dur` 决定余音长度 —— 衰减系数按 `2.2 / dur` 缩放，
    所以短锣是「同一面锣被按住」，而不是把长锣生硬截断。
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    scale = 2.2 / max(dur, 0.35)
    ratios = [1.0, 1.47, 2.09, 2.83, 3.61, 4.72, 6.13]
    gains = [1.0, 0.62, 0.44, 0.33, 0.22, 0.14, 0.08]
    out = np.zeros(n)
    base = f_of("D3")
    for r, g in zip(ratios, gains):
        if base * r > SR * 0.45:
            break
        out += g * np.exp(-(0.50 + 0.30 * r) * scale * t) * np.sin(2 * np.pi * base * r * t)
    out += 0.16 * np.exp(-t * 60.0) * _lp(_rng(33).uniform(-1, 1, n), 2)
    return amp * np.minimum(1.0, t * 320.0) * out


# ---------------- 皮膜与破坏 ----------------

def drum(f0: float = 178.0, f1: float = 52.0, dur: float = 0.5, amp: float = 1.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    freq = f1 + (f0 - f1) * np.exp(-t * 24.0)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 7.5)
    click = _lp(_rng(int(f0) % 7919).uniform(-1, 1, n), 2) * np.exp(-t * 90.0) * 0.4
    return amp * (body + click)


def destroy(amp: float = 0.75) -> np.ndarray:
    """摧毁单位：噪声爆裂 + 音高快速下坠，表达「崩解」。"""
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    crash = _lp(_rng(55).uniform(-1, 1, n), 1) * np.exp(-t * 13.0)
    freq = 300.0 * np.exp(-t * 7.0) + 46.0
    fall = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 5.0) * 0.55
    return amp * (crash * 0.65 + fall)


def round_start(amp: float = 0.72) -> np.ndarray:
    """回合开始：一记鼓 + 一记**短**锣。

    【为什么必须短】回合开始是当局内反复触发的提示音（一局要响十几次），
    长余音会互相叠成噪音。这里用 `gong(0.85)`，只剩「锣被敲了一下」的骨架。
    """
    g = gong(0.85, 0.45)
    d = drum(200.0, 56.0, 0.45, 0.6)
    n = max(len(g), len(d))
    out = np.zeros(n)
    out[: len(g)] += g
    out[: len(d)] += d
    return amp * out


def round_end(amp: float = 0.66) -> np.ndarray:
    """回合结束：两声下行鼓。"""
    n = int(0.85 * SR)
    out = np.zeros(n)
    d1 = drum(178.0, 54.0, 0.40, 0.7)
    d2 = drum(140.0, 44.0, 0.46, 0.6)
    out[: len(d1)] += d1
    off = int(0.24 * SR)
    out[off: off + len(d2)] += d2
    return amp * out


def win(amp: float = 0.8) -> np.ndarray:
    """胜利：三音上行编钟（宫 → 徵 → 宫）。"""
    n = int(1.7 * SR)
    out = np.zeros(n)
    for i, (nm, off) in enumerate([("D4", 0.0), ("A4", 0.17), ("D5", 0.34)]):
        b = bell(f_of(nm), 1.35, 0.62 - i * 0.06)
        s = int(off * SR)
        out[s: s + len(b)] += b
    return amp * out


def lose(amp: float = 0.75) -> np.ndarray:
    """失败：三音下行（宫 → 羽 → 徵），音色转暗。"""
    n = int(2.0 * SR)
    out = np.zeros(n)
    for i, (nm, off) in enumerate([("D4", 0.0), ("B3", 0.22), ("A3", 0.44)]):
        b = bell(f_of(nm), 1.55, 0.60 - i * 0.05)
        s = int(off * SR)
        out[s: s + len(b)] += b
    return amp * out


def error(amp: float = 0.42) -> np.ndarray:
    """操作被拒：一声闷响，不刺耳但明确。"""
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    freq = 210.0 * np.exp(-t * 4.0) + 128.0
    out = np.sin(2 * np.pi * np.cumsum(freq) / SR)
    out += 0.32 * np.sin(2 * np.pi * 2.1 * np.cumsum(freq) / SR)
    return amp * np.minimum(1.0, t * 700.0) * np.exp(-t * 15.0) * out


# ---------------- 输出 ----------------

EFFECTS = {
    "ui_click": click,
    "ui_hover": hover,
    "card_place": card_place,
    "card_draw": card_draw,
    "tactic": tactic,
    "gong": gong,
    "destroy": destroy,
    "round_start": round_start,
    "round_end": round_end,
    "win": win,
    "lose": lose,
    "error": error,
}


def write_wav(path: str, mono: np.ndarray, peak: float = 0.92):
    m = float(np.max(np.abs(mono)))
    if m > 0:
        mono = mono * (peak / m)
    mono = np.tanh(mono * 1.02) * 0.97              # 软限幅
    k = int(0.004 * SR)                              # 4ms 首尾淡化，防爆音
    if k > 0 and len(mono) > 2 * k:
        ramp = np.linspace(0.0, 1.0, k)
        mono[:k] *= ramp
        mono[-k:] *= ramp[::-1]
    data = np.ascontiguousarray(mono, dtype=np.float32)
    with sf.SoundFile(path, mode="w", samplerate=SR, channels=1,
                      format="WAV", subtype="PCM_16") as f:
        for i in range(0, data.shape[0], 8192):
            f.write(data[i:i + 8192])
    return os.path.getsize(path), len(mono) / SR


def main() -> int:
    print("合成音效 -> %s" % OUT_DIR)
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name, fn in EFFECTS.items():
        path = os.path.join(OUT_DIR, name + ".wav")
        size, dur = write_wav(path, fn())
        total += size
        print("  -> %-14s %5.2f 秒  %5.1f KB" % (name + ".wav", dur, size / 1024.0))
    print("共 %d 个音效，合计 %.1f KB" % (len(EFFECTS), total / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
