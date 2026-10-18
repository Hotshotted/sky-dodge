#!/usr/bin/env python3
"""Generates the game's placeholder audio into audio/ (22050 Hz, mono, 16 bit WAV). Everything is synthesised here from
sines, saws and filtered noise: no samples, no downloads. Run: python3 tools/make_audio.py  (needs numpy)."""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT, exist_ok=True)

def t_(dur): return np.arange(int(SR * dur)) / SR
def env(n, a=0.005, r=0.1):
    e = np.ones(n); na = max(int(a * SR), 1); nr = max(int(r * SR), 1)
    e[:na] = np.linspace(0, 1, na); e[-nr:] *= np.linspace(1, 0, nr); return e
def decay(t, k): return np.exp(-t * k)
def lowpass(x, cutoff):
    """one-pole low-pass; cutoff in Hz (a number or an array per sample)"""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        a = 1.0 - np.exp(-2 * np.pi * c[i] / SR)
        s += a * (x[i] - s); y[i] = s
    return y
def highpass(x, cutoff): return x - lowpass(x, cutoff)
def noise(n): return rng.uniform(-1, 1, n)
def sine(f, t): return np.sin(2 * np.pi * f * t)
def saw(f, t): return 2 * ((f * t) % 1.0) - 1
def square(f, t): return np.sign(np.sin(2 * np.pi * f * t))
def tri(f, t): return 2 * np.abs(2 * ((f * t) % 1.0) - 1) - 1
def save(name, x, peak=0.8):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x))
    if m > 0: x = x / m * peak
    pcm = (x * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

def whoosh(dur, lo, hi, amp=1.0):
    n = int(SR * dur); t = t_(dur)
    sweep = lo + (hi - lo) * np.sin(np.pi * t / dur)           # the filter opens and closes: a pass-by
    x = lowpass(noise(n), sweep) * (np.sin(np.pi * t / dur) ** 1.5)
    return x * amp

def bell(f, dur, k=5.0):
    t = t_(dur)
    return (sine(f, t) + 0.5 * sine(f * 2.01, t) + 0.25 * sine(f * 3.02, t)) * decay(t, k) * env(len(t), 0.002, 0.05)

# ---- one-shots
save("whoosh", whoosh(0.45, 400, 3500))
save("whoosh_big", whoosh(0.7, 300, 5200) + 0.5 * whoosh(0.7, 150, 900))
b = whoosh(0.9, 300, 5200) + 0.4 * whoosh(0.9, 150, 900)
for i, f in enumerate([1046.5, 1318.5, 1568.0]):
    seg = bell(f, 0.8); b[int(0.08 * SR) * i:int(0.08 * SR) * i + len(seg)] += 0.35 * seg[: len(b) - int(0.08 * SR) * i]
save("barnstormer", b)
t = t_(0.3); save("pickup", (sine(880 * (1 + 0.5 * (t > 0.08)), t) + 0.4 * sine(1760 * (1 + 0.5 * (t > 0.08)), t)) * decay(t, 7) * env(len(t), 0.002, 0.05))
x = np.zeros(int(SR * 0.45))
for i, st in enumerate([0.0, 0.07, 0.15]):
    k = int(st * SR); n = int(0.18 * SR); tt = t_(0.18)
    x[k:k + n] += highpass(lowpass(noise(n), 2500), 200) * decay(tt, 22) + 0.4 * sine(150 - 30 * i, tt) * decay(tt, 30)
save("crunch", x)
n = int(SR * 1.1); t = t_(1.1)
crash = lowpass(noise(n), 900 * decay(t, 3) + 120) * decay(t, 3.5) + 0.9 * sine(70 * decay(t, 1.2) + 35, t) * decay(t, 4)
for st in (0.05, 0.14, 0.31, 0.5):
    k = int(st * SR); m = int(0.08 * SR); crash[k:k + m] += highpass(noise(m), 1500) * decay(t_(0.08), 40) * 0.6
save("crash", crash)
x = np.zeros(int(SR * 0.5))
for i, f in enumerate([523.3, 659.3, 784.0]):
    seg = tri(f, t_(0.3)) * decay(t_(0.3), 8) * env(int(SR * 0.3), 0.003, 0.05); k = int(0.07 * SR) * i; x[k:k + len(seg)] += seg
save("pick_open", x)
t = t_(0.28); save("pick_select", (sine(988 , t) * (t < 0.09) + sine(1319, t) * (t >= 0.09)) * decay(t % 0.09, 14) * env(len(t), 0.002, 0.05))
x = whoosh(1.2, 250, 4500) + 0.5 * lowpass(noise(int(SR * 1.2)), 1200) * np.sin(np.pi * t_(1.2) / 1.2)
save("speed_whoosh", x)
t = t_(0.035); save("tick", (sine(2400, t) * decay(t, 90)))
t = t_(0.06); save("tap", (sine(1500, t) + 0.5 * noise(len(t)) * 0.3) * decay(t, 70))

# ---- loops
# engine: one second, 55 Hz (55 whole cycles: the loop is seamless); pitch_scale raises it with speed
t = t_(1.0)
eng = lowpass(saw(55, t) * 0.7 + square(110, t) * 0.3 + sine(27.5, t) * 0.5, 700) * (0.75 + 0.25 * sine(27.5, t))
save("engine", eng, 0.6)
# wind: two seconds of filtered noise with the ends cross-faded so it loops
n = int(SR * 2.0); w = lowpass(noise(n + 4000), 1800)
xf = 2000; w[:xf] = w[:xf] * np.linspace(0, 1, xf) + w[n:n + xf] * np.linspace(1, 0, xf)
save("wind", w[:n], 0.6)
# music: 120 BPM, 8 beats = 4 s, Am then F. Three layers that all loop with the same length
BEAT = 0.5; LOOP = 4.0
def place(buf, seg, t0):
    k = int(t0 * SR); m = min(len(seg), len(buf) - k)
    if m > 0: buf[k:k + m] += seg[:m]
chords = [([110.0, 220.0, 261.63, 329.63], 0.0), ([87.31, 174.61, 220.0, 261.63], 2.0)]
base = np.zeros(int(SR * LOOP))
for notes, t0 in chords:
    d = 2.0; tt = t_(d)
    pad = sum(tri(f, tt) for f in notes[1:]) * 0.25
    place(base, pad * env(len(tt), 0.25, 0.4), t0)
    for beat in (0, 1):   # bass: two long notes per chord
        seg = sine(notes[0], t_(0.9)) * decay(t_(0.9), 2.5) * env(int(SR * 0.9), 0.01, 0.15)
        place(base, seg * 0.9, t0 + beat * 1.0)
rhythm = np.zeros(int(SR * LOOP))
for b in range(8):
    tk = t_(0.25); kick = sine(130 * np.exp(-tk * 18) + 42, tk) * decay(tk, 10)
    if b % 1 == 0: place(rhythm, kick, b * BEAT)
    hat = highpass(noise(int(SR * 0.05)), 5000) * decay(t_(0.05), 60)
    place(rhythm, hat * 0.5, b * BEAT + BEAT / 2)
    if b % 4 == 2:
        sn = (lowpass(highpass(noise(int(SR * 0.18)), 400), 4500) * decay(t_(0.18), 18) + 0.4 * sine(190, t_(0.18)) * decay(t_(0.18), 25))
        place(rhythm, sn * 0.8, b * BEAT)
full = np.zeros(int(SR * LOOP))
penta = {0: [440.0, 523.25, 659.25, 783.99, 880.0], 1: [349.23, 440.0, 523.25, 698.46, 880.0]}
pat = [0, 2, 4, 2, 3, 1, 2, 4]
for step in range(16):   # 8th notes
    ch = step // 8; f = penta[ch][pat[step % 8]]
    seg = (square(f, t_(0.22)) * 0.5 + saw(f * 2.0, t_(0.22)) * 0.2) * decay(t_(0.22), 11) * env(int(SR * 0.22), 0.004, 0.05)
    place(full, lowpass(seg, 3500) * 0.7, step * BEAT / 2)
for notes, t0 in chords:
    tt = t_(2.0); place(full, sum(sine(f * 2, tt) for f in notes[1:]) * 0.12 * env(len(tt), 0.3, 0.5), t0)
mix = base * 1.0 / np.max(np.abs(base))
save("music_base", base, 0.55)
save("music_rhythm", rhythm, 0.55)
save("music_full", full, 0.5)
print("audio written to", os.path.abspath(OUT))
