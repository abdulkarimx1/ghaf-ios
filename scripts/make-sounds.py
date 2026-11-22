#!/usr/bin/env python3
"""Generate Ghaf's short, warm UI sounds using only Python's standard library."""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Ghaf", "Resources", "Sounds")


def write(name, samples, peak_db):
    os.makedirs(OUT, exist_ok=True)
    fade_samples = int(RATE * 0.005)
    end = len(samples) - 1
    samples = [sample * min(1.0, i / fade_samples, (end - i) / fade_samples)
               for i, sample in enumerate(samples)]
    peak = max((abs(x) for x in samples), default=0.0)
    if peak:
        target = 10 ** (peak_db / 20)
        samples = [x * target / peak for x in samples]
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, s)) * 32767)) for s in samples))


def envelope(t, duration, attack=0.004, decay=0.08):
    fade = min(1.0, t / 0.005, (duration - t) / 0.005)
    return max(0, fade) * min(1.0, t / attack) * math.exp(-max(0, t - attack) / decay)


def glide(name, start, end, duration, peak_db, harmonic=0.0, decay=0.08):
    peak = 10 ** (peak_db / 20)
    count = int(RATE * duration)
    out = []
    phase = 0.0
    for i in range(count):
        t = i / RATE
        f = start + (end - start) * t / duration
        phase += 2 * math.pi * f / RATE
        out.append(peak * envelope(t, duration, decay=decay) * (math.sin(phase) + harmonic * math.sin(phase * 2)))
    write(name, out, peak_db)


def bell_sequence(name, notes, spacing, duration, peak_db, decay):
    peak = 10 ** (peak_db / 20)
    count = int(RATE * duration)
    out = [0.0] * count
    for start, freq in notes:
        phase = 0.0
        for i in range(int(RATE * 0.42)):
            t = i / RATE
            index = int(start * RATE) + i
            if index >= count:
                break
            phase += 2 * math.pi * freq / RATE
            env = min(1.0, t / 0.004) * math.exp(-t / decay)
            out[index] += peak * env * (math.sin(phase) + 0.1 * math.sin(phase * 3))
    write(name, out, peak_db)


glide("orb_on", 520, 660, 0.110, -24, harmonic=10 ** (-18 / 20), decay=0.055)
glide("orb_off", 660, 494, 0.100, -26, harmonic=10 ** (-18 / 20), decay=0.052)
bell_sequence("added", [(0.0, 659), (0.070, 988)], 0.070, 0.280, -20, 0.180)

# One-pole low-pass noise falling from 1.8 kHz toward 300 Hz plus a low descending tone.
random.seed(129)
duration = 0.220
count = int(RATE * duration)
peak = 10 ** (-24 / 20)
noise, low = [], 0.0
phase = 0.0
for i in range(count):
    t = i / RATE
    cutoff = 1800 + (300 - 1800) * t / duration
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    low += alpha * (random.uniform(-1, 1) - low)
    freq = 220 + (150 - 220) * t / duration
    phase += 2 * math.pi * freq / RATE
    noise.append(peak * envelope(t, duration, decay=0.095) * (0.7 * low + 0.3 * math.sin(phase)))
write("deleted", noise, -24)

bell_sequence("streak", [(0.0, 523), (0.090, 659), (0.180, 784)], 0.090, 0.600, -20, 0.35)
for index, factor in enumerate((0.97, 1.0, 1.03), start=1):
    duration = 0.030
    peak = 10 ** (-32 / 20)
    write("tick" if index == 1 else f"tick_{index}", [
        peak * envelope(i / RATE, duration, attack=0.002, decay=0.012)
        * math.sin(2 * math.pi * 1200 * factor * i / RATE)
        for i in range(int(RATE * duration))
    ], -32)
