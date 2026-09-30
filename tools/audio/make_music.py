# -*- coding: utf-8 -*-
"""《七雄策》背景音乐合成器（纯程序合成，无外部采样）。

音色设计：
  编钟 bell()   —— 非谐泛音叠加 + 极慢衰减（中式钟「一钟双音」的泛音比）
  古筝 pluck()  —— 谐波叠加，高次谐波衰减更快（拨弦的自然亮度衰减）
  战鼓 drum()   —— 音高快速下滑的正弦 + 鼓槌噪声瞬态
  埙/箫 flute() —— 正弦 + 少量二次谐波 + 气息噪声 + 颤音
  低音 drone()  —— 铺底持续音，弱颤音起伏

调式：D 宫五声音阶（宫 D / 商 E / 角 #F / 徵 A / 羽 B），战国风格的核心。

输出：assets/music/menu.ogg（主菜单·庄重悠远）、faction.ogg（阵营选择·肃静择国）、
battle.ogg（对局·紧张肃杀）。三者都是**整数小节**长度，末尾 25ms 淡出 + 开头 25ms 淡入，循环时听不出接缝。
"""
import os
import sys

import numpy as np
import soundfile as sf

SR = 44100
OUT_DIR = r"E:/goodot_work/七雄策/assets/music"


# ---------------- 音高 ----------------

def f_of(name: str) -> float:
    """音名 -> 频率（以 A4 = 440 为基准）。只用 D 宫五声：D E F# A B。"""
    letter, octave = name[:-1], int(name[-1])
    rel = {"D": -7, "E": -5, "F#": -3, "A": 0, "B": 2}[letter]
    return 440.0 * 2.0 ** ((rel + (octave - 4) * 12) / 12.0)


# ---------------- 乐器 ----------------

def pluck(f: float, dur: float, amp: float = 1.0, bright: float = 1.0) -> np.ndarray:
    """拨弦（古筝 / 琵琶）。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    k = 1
    while k <= 14:
        fk = f * k
        if fk > SR * 0.45:
            break
        # 高次谐波衰减更快 —— 这是拨弦「起音亮、余音暖」的来源
        env = np.exp(-(3.4 + 1.05 * k) * t)
        out += (bright ** ((k - 1) * 0.3)) / (k ** 1.3) * np.sin(2 * np.pi * fk * t + 0.4 * k) * env
        k += 1
    # 指甲触弦的瞬态
    out += 0.16 * np.exp(-t * 190) * np.sin(2 * np.pi * f * 4.5 * t)
    attack = np.minimum(1.0, t * 900.0)
    return amp * attack * out


def bell(f: float, dur: float, amp: float = 1.0) -> np.ndarray:
    """编钟。泛音比取中式钟的典型值（含 2.76 / 5.40 这类非谐分音）。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    ratios = [1.0, 2.0, 2.76, 3.76, 5.40, 6.85, 9.10]
    gains = [1.0, 0.50, 0.42, 0.26, 0.16, 0.09, 0.05]
    out = np.zeros(n)
    for r, g in zip(ratios, gains):
        if f * r > SR * 0.45:
            break
        out += g * np.exp(-(0.52 + 0.42 * r) * t) * np.sin(2 * np.pi * f * r * t)
    # 钟槌击打的金属噪声
    rng = np.random.default_rng(int(f) % 9973)
    out += 0.10 * np.exp(-t * 95.0) * rng.uniform(-1, 1, n)
    return amp * np.minimum(1.0, t * 520.0) * out


def drum(f0: float = 178.0, f1: float = 52.0, dur: float = 0.55,
         amp: float = 1.0, punch: float = 1.0) -> np.ndarray:
    """战鼓：皮膜张力松弛造成的音高下滑 + 鼓槌击打噪声。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    freq = f1 + (f0 - f1) * np.exp(-t * 24.0)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t * 7.0)
    rng = np.random.default_rng(int(f0) % 7919)
    noise = rng.uniform(-1, 1, n)
    for _ in range(2):                       # 简易一阶低通，去掉刺耳的高频
        noise = np.convolve(noise, [0.5, 0.5], mode="same")
    click = noise * np.exp(-t * 80.0) * 0.45 * punch
    return amp * (body + click)


def flute(f: float, dur: float, amp: float = 1.0, vib: float = 5.0) -> np.ndarray:
    """埙 / 箫：气息感 + 颤音。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    fm = 1.0 + 0.0026 * np.sin(2 * np.pi * vib * t)
    body = np.sin(2 * np.pi * f * t * fm) + 0.22 * np.sin(2 * np.pi * 2 * f * t * fm)
    rng = np.random.default_rng(int(f) % 6151)
    air = rng.uniform(-1, 1, n) * 0.028
    env = np.minimum(1.0, t * 5.0) * np.exp(-np.maximum(0.0, t - dur * 0.72) * 3.2)
    return amp * env * (body + air)


def drone(f: float, dur: float, amp: float = 1.0) -> np.ndarray:
    """低音铺底。起伏周期取整数倍，保证循环处相位连续。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * f * t) + 0.30 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3 * f * t)
    lfo_period = 16.0
    lfo = 0.80 + 0.20 * np.sin(2 * np.pi * t / lfo_period - np.pi / 2)
    return amp * out * lfo


# ---------------- 混音工具 ----------------

class Track:
    """立体声混音缓冲。位置一律用「秒」表达，方便按小节谱曲。"""

    def __init__(self, seconds: float):
        self.n = int(seconds * SR)
        self.buf = np.zeros((2, self.n), dtype=np.float64)

    def add(self, mono: np.ndarray, at: float, amp: float = 1.0, pan: float = 0.0):
        """pan: -1 全左 / 0 居中 / +1 全右。"""
        start = int(at * SR)
        if start >= self.n:
            return
        seg = mono[: self.n - start] * amp
        left = np.sqrt((1.0 - pan) / 2.0)
        right = np.sqrt((1.0 + pan) / 2.0)
        self.buf[0, start:start + len(seg)] += seg * left * 1.4142
        self.buf[1, start:start + len(seg)] += seg * right * 1.4142

    def add_stereo(self, mono: np.ndarray, at: float, amp: float = 1.0, width_ms: float = 9.0):
        """轻微左右延迟，给钟 / 筝一点空间宽度。"""
        self.add(mono, at, amp, pan=-0.18)
        self.add(mono, at + width_ms / 1000.0, amp * 0.85, pan=0.18)

    def reverb(self, mix: float = 0.30):
        """简易多抽头回声，制造厅堂感。作用于整体，保持左右独立。"""
        taps = [0.041, 0.067, 0.093, 0.131, 0.179]
        out = self.buf.copy()
        for i, d in enumerate(taps):
            k = int(d * SR)
            if k >= self.n:
                continue
            g = (0.40 ** (i + 1)) * mix * 2.4
            out[:, k:] += self.buf[:, : self.n - k] * g
        self.buf = out

    def master(self, peak: float = 0.90, fade_ms: float = 25.0):
        """归一化 + 首尾短淡化（让循环接缝听不出来）。

        【为什么不用 tanh 软限幅】归一化已经把峰值钉在 `peak`，再叠一层 tanh
        只会把整体电平一起压低（实测把 0.90 压到 0.68、RMS 掉 3dB 以上），
        对游戏 BGM 反而偏安静。这里改用硬边界保险 —— 只有在极端叠加时才可能触及。
        """
        m = float(np.max(np.abs(self.buf)))
        if m > 0:
            self.buf *= peak / m
        self.buf = np.clip(self.buf, -0.995, 0.995)
        k = int(fade_ms / 1000.0 * SR)
        if k > 0:
            ramp = np.linspace(0.0, 1.0, k)
            self.buf[:, :k] *= ramp
            self.buf[:, -k:] *= ramp[::-1]
        return self.buf


def write_ogg(path: str, stereo: np.ndarray, quality: float = 0.55):
    """写 OGG Vorbis。

    【为什么必须分块】soundfile 的 `write()` 会把整块数据一次性交给 libsndfile，
    对 2 × 240 万采样的大数组会触发 **C 层栈溢出**（进程直接 127 退出、无 traceback，
    只有 faulthandler 能看到 `Windows fatal exception: stack overflow`）。
    用 `blocksize` 分块喂进去即可，听感完全一致。
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.ascontiguousarray(stereo.T, dtype=np.float32)
    with sf.SoundFile(path, mode="w", samplerate=SR, channels=2,
                      format="OGG", subtype="VORBIS") as f:
        try:
            f.compression_level = quality
        except Exception:
            pass
        for i in range(0, data.shape[0], 8192):
            f.write(data[i:i + 8192])
    size = os.path.getsize(path)
    print("  -> %-28s %6.1f 秒  %5.2f MB" % (os.path.basename(path), len(stereo[0]) / SR, size / 1048576.0))


# ---------------- 曲目一：主菜单（庄重悠远） ----------------
# 70 BPM，4/4，每小节 3.42857 秒，共 16 小节 ≈ 54.86 秒

def build_menu() -> np.ndarray:
    bpm = 70.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 16
    total = bar * bars
    tr = Track(total)

    # 低音铺底：D2 一直托着，循环处相位连续
    tr.add(drone(f_of("D2"), total, 0.20), 0.0, pan=0.0)

    # 编钟：每 2 小节敲一次，走 D → A → B → E(商) 的骨架
    bell_plan = [
        (0, "D4"), (2, "A4"), (4, "B4"), (6, "E4"),
        (8, "D4"), (10, "A4"), (12, "F#4"), (14, "D4"),
    ]
    for b, nm in bell_plan:
        tr.add_stereo(bell(f_of(nm), 5.2, 0.42), b * bar, amp=1.0, width_ms=12.0)

    # 古筝旋律：每 4 小节一句，句尾留白（悠远感来自留白）
    melody = [
        # (小节内拍数, 音名, 时值拍, 音量) —— 每句 4 小节
        [(0.0, "D4", 2.0, .30), (2.0, "E4", 1.0, .24), (3.0, "F#4", 1.0, .24),
         (4.0, "A4", 2.5, .30), (6.5, "B4", 1.0, .22), (7.5, "A4", 0.5, .20),
         (8.0, "F#4", 3.0, .28), (11.0, "E4", 1.0, .22),
         (12.0, "D4", 4.0, .26)],
        [(0.0, "A4", 2.0, .30), (2.0, "B4", 1.0, .24), (3.0, "A4", 1.0, .22),
         (4.0, "F#4", 2.0, .28), (6.0, "E4", 2.0, .24),
         (8.0, "D4", 2.5, .30), (10.5, "E4", 1.5, .22),
         (12.0, "D4", 4.0, .26)],
        [(0.0, "B4", 2.0, .28), (2.0, "A4", 1.0, .24), (3.0, "F#4", 2.0, .24),
         (5.0, "E4", 1.0, .22), (6.0, "F#4", 2.0, .26),
         (8.0, "A4", 3.0, .28), (11.0, "B4", 1.0, .22),
         (12.0, "D5", 4.0, .28)],
        [(0.0, "F#4", 2.0, .28), (2.0, "E4", 2.0, .24),
         (4.0, "D4", 2.0, .30), (6.0, "E4", 2.0, .24),
         (8.0, "F#4", 2.0, .26), (10.0, "E4", 2.0, .22),
         (12.0, "D4", 4.0, .28)],
    ]
    for phrase_i, phrase in enumerate(melody):
        t0 = phrase_i * 4.0 * bar
        for bpos, nm, beats, amp in phrase:
            dur = beats * beat
            tr.add(pluck(f_of(nm), max(dur, 1.6), amp), t0 + bpos * beat, pan=-0.10)

    # 埙：在编钟之间补长音，进一步拉出空旷感
    for b, nm in [(1, "A4"), (5, "F#4"), (9, "E4"), (13, "A4")]:
        tr.add(flute(f_of(nm), 2.6 * beat, 0.16), b * bar + 2.0 * beat, pan=0.14)

    tr.reverb(mix=0.34)
    return tr.master(peak=0.90)


# ---------------- 曲目二：阵营选择（肃静择国） ----------------
# 76 BPM，4/4，共 8 小节 ≈ 25.26 秒

def build_faction() -> np.ndarray:
    bpm = 76.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 8
    total = bar * bars
    tr = Track(total)

    # 以 D2 持续低音托住画面，保持与主菜单和战斗曲相同的调式根音。
    tr.add(drone(f_of("D2"), total, 0.13), 0.0)
    # 每两小节一声编钟，给“择国”操作留下明确的呼吸点。
    for b, nm in [(0, "D4"), (2, "A4"), (4, "F#4"), (6, "D4")]:
        tr.add_stereo(bell(f_of(nm), 3.2, 0.30), b * bar, amp=1.0, width_ms=14.0)

    # 短句古筝 + 稀疏埙声，气质安静但仍属于同一套战国音色。
    motif = ["D4", "F#4", "A4", "B4", "A4", "F#4", "E4", "D4"]
    for i, nm in enumerate(motif):
        at = (i * 0.75) * beat
        tr.add(pluck(f_of(nm), 1.4, 0.20), at, pan=-0.08)
        if i % 2 == 1:
            tr.add(flute(f_of(nm), 1.6 * beat, 0.08), at + 0.25 * beat, pan=0.18)

    tr.reverb(mix=0.30)
    return tr.master(peak=0.86)


# ---------------- 曲目三：对局（紧张肃杀） ----------------
# 108 BPM，4/4，每小节 2.22222 秒，共 20 小节 ≈ 44.44 秒

def build_battle() -> np.ndarray:
    bpm = 108.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 20
    total = bar * bars
    tr = Track(total)

    # 低音：D2 的断奏，每小节两下，给推进感
    for b in range(bars):
        t0 = b * bar
        tr.add(drum(96.0, 46.0, 0.42, 0.30, 0.6), t0, pan=-0.08)
        tr.add(drum(96.0, 46.0, 0.34, 0.22, 0.5), t0 + 2.0 * beat, pan=-0.08)

    # 战鼓型：咚 · 哒咚 · 哒（每小节固定，第 4 拍后半加花）
    for b in range(bars):
        t0 = b * bar
        tr.add(drum(182.0, 54.0, 0.58, 0.62), t0, pan=-0.05)
        tr.add(drum(150.0, 40.0, 0.30, 0.34), t0 + 1.5 * beat, pan=0.08)
        tr.add(drum(182.0, 54.0, 0.50, 0.52), t0 + 2.0 * beat, pan=-0.05)
        tr.add(drum(170.0, 48.0, 0.40, 0.40), t0 + 3.0 * beat, pan=0.10)
        # 每 4 小节一次鼓点加花
        if b % 4 == 3:
            tr.add(drum(205.0, 62.0, 0.26, 0.30), t0 + 3.5 * beat, pan=0.14)
            tr.add(drum(160.0, 44.0, 0.24, 0.26), t0 + 3.75 * beat, pan=-0.14)

    # 古筝：连续十六分琶音，每 4 小节换一次音型（肃杀感来自密集与重复）
    patterns = [
        ["D4", "A4", "D5", "A4"],
        ["A4", "E5", "A4", "F#4"],
        ["B4", "F#5", "B4", "A4"],
        ["D4", "A4", "D5", "E5"],
        ["F#4", "B4", "F#5", "B4"],
    ]
    step = beat / 2.0                      # 八分音符（密集但不糊）
    for b in range(bars):
        pat = patterns[(b // 4) % len(patterns)]
        t0 = b * bar
        for i in range(8):
            nm = pat[i % len(pat)] if i % 2 == 0 else pat[(i // 2 + 2) % len(pat)]
            tr.add(pluck(f_of(nm), 0.55, 0.15), t0 + i * step, pan=0.16)

    # 编钟：每 4 小节用低音钟点一下乐句头，做段落分隔
    for b in [0, 4, 8, 12, 16]:
        tr.add_stereo(bell(f_of("D3"), 3.6, 0.30), b * bar, amp=1.0, width_ms=10.0)

    # 埙：稀疏的高音长音，制造不安
    for b, nm in [(3, "F#5"), (7, "E5"), (11, "D5"), (15, "F#5"), (19, "D5")]:
        tr.add(flute(f_of(nm), 1.4 * beat, 0.13, vib=6.2), b * bar + 2.0 * beat, pan=0.20)

    tr.reverb(mix=0.22)
    return tr.master(peak=0.92)


def main() -> int:
    print("合成背景音乐 -> %s" % OUT_DIR)
    write_ogg(os.path.join(OUT_DIR, "menu.ogg"), build_menu())
    write_ogg(os.path.join(OUT_DIR, "faction.ogg"), build_faction())
    write_ogg(os.path.join(OUT_DIR, "battle.ogg"), build_battle())
    print("完成。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
