#!/usr/bin/env python3
"""Synthesised placeholder audio for every id of art/source/audio/plan.json (no fal call, no sample).

Used while the fal lot cannot run: same ids, so the game, the tests and tools/audio/process_audio.py work
unchanged, and a later `tools/fal/audio.py run --all` + `process_audio.py` replaces them one by one.
Everything is made here from sine partials and seeded noise (original, deterministic).

  python3 tools/audio/synth_placeholders.py [out_dir]   # default art/source/audio/placeholder/
"""
import json
import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
NOTE = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def env_adsr(n, a, d, s, r):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n))
    e[:na] = np.linspace(0, 1, na)
    nd = max(0, min(nd, n - na))
    e[na:na + nd] = np.linspace(1, s, nd)
    nr = max(1, min(nr, n))
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def tone(freq, seconds, partials=((1, 1.0),), decay=None, phase=0.0):
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for mult, amp in partials:
        f = freq * mult
        if f < SR / 2.2:
            out += amp * np.sin(2 * np.pi * f * t + phase * mult)
    if decay:
        out *= np.exp(-t / decay)
    return out


def noise(seconds, rng):
    return rng.standard_normal(int(seconds * SR))


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], 'bandpass', fs=SR, output='sos'), x)


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, 'lowpass', fs=SR, output='sos'), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, 'highpass', fs=SR, output='sos'), x)


def place(buf, sig, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n]


def place_wrap(buf, sig, at):
    """Adds `sig` at `at` seconds, wrapping past the end (seamless loops)."""
    i = int(at * SR) % len(buf)
    while len(sig):
        n = min(len(sig), len(buf) - i)
        buf[i:i + n] += sig[:n]
        sig, i = sig[n:], 0


def reverb_ir(seconds, rng, bright=4000.0):
    n = int(seconds * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (n / 5.0))
    return lowpass(ir, bright) / np.sqrt(np.sum(ir ** 2))


def circular_reverb(x, ir):
    """Reverb by circular convolution: the tail wraps onto the start, so a loop stays seamless."""
    n = len(x)
    h = np.zeros(n)
    m = min(len(ir), n)
    h[:m] = ir[:m]
    return np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(h)))


def linear_reverb(x, ir, tail):
    y = np.concatenate([x, np.zeros(int(tail * SR))])
    return fftconvolve(y, ir)[:len(y)]


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


# --- Instruments ---------------------------------------------------------------------------------


def pluck(freq, seconds=1.6, bright=1.0):
    parts = [(1, 1.0), (2, 0.5 * bright), (3, 0.25 * bright), (4, 0.12 * bright), (5, 0.06 * bright)]
    s = tone(freq, seconds, parts, decay=seconds / 3.5)
    a = int(0.004 * SR)
    s[:a] *= np.linspace(0, 1, a)
    return s


def pad(freq, seconds, rng):
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for det in (-0.12, 0.0, 0.13):
        f = freq * 2 ** (det / 12)
        for mult, amp in ((1, 1.0), (2, 0.3), (3, 0.12)):
            out += amp * np.sin(2 * np.pi * f * mult * t + rng.uniform(0, 6.28))
    return out * env_adsr(len(t), seconds * 0.3, 0.1, 1.0, seconds * 0.35) / 3


def bell_voice(freq, seconds, rng=None, strike=0.6):
    """Inharmonic struck-bell partials (hum, prime, tierce, quint, nominal and upper), slow beating."""
    ratios = [(0.5, 0.55, 3.0), (1.0, 1.0, 2.2), (1.183, 0.6, 1.6), (1.506, 0.45, 1.3), (2.0, 0.55, 1.0),
              (2.514, 0.3, 0.7), (2.662, 0.22, 0.6), (3.011, 0.18, 0.5), (4.166, 0.1, 0.3), (5.433, 0.06, 0.2)]
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for r, amp, dec in ratios:
        f = freq * r
        beat = 1 + 0.15 * np.sin(2 * np.pi * (0.7 + r * 0.3) * t)
        out += amp * beat * np.sin(2 * np.pi * f * t) * np.exp(-t / (dec * seconds / 3.0))
    if rng is not None:
        click = highpass(noise(0.03, rng), 2000) * np.linspace(1, 0, int(0.03 * SR)) * strike
        out[:len(click)] += click
    return out


def kick(rng):
    t = t_axis(0.35)
    f = 50 + 90 * np.exp(-t / 0.04)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)


def drum(rng, lo=120, hi=900, dec=0.18):
    n = noise(dec * 3, rng)
    return bandpass(n, lo, hi) * np.exp(-t_axis(dec * 3) / dec) * 2.5


def shaker(rng):
    return highpass(noise(0.08, rng), 5000) * np.exp(-t_axis(0.08) / 0.02) * 0.6


# --- Music ---------------------------------------------------------------------------------------

MUSIC = {
    # key, mode, bpm, beats per bar, progression (scale degrees), flavour
    'music_title': ('D', 'major', 72, 4, [0, 5, 3, 4], 'guitar_celesta'),
    'music_aubelin': ('G', 'major', 92, 4, [0, 3, 4, 0, 5, 3, 4, 4], 'village'),
    'music_whispering_wood': ('E', 'minor', 84, 4, [0, 5, 2, 6], 'harp'),
    'music_lantern_mire': ('A', 'minor', 70, 4, [0, 5, 0, 6], 'glass'),
    'music_watch_ruins': ('C', 'minor', 66, 4, [0, 5, 3, 4], 'cello'),
    'music_cloister_night': ('F#', 'minor', 68, 4, [0, 5, 3, 4], 'musicbox'),
    'music_combat': ('D', 'minor', 132, 4, [0, 5, 6, 4, 0, 5, 3, 4], 'battle'),
    'music_boss_morvaine': ('B', 'minor', 138, 3, [0, 0, 5, 5, 3, 3, 4, 4], 'waltz'),
}


def chord(root_midi, scale, degree, size=3):
    notes = []
    for k in range(size):
        d = degree + 2 * k
        notes.append(root_midi + scale[d % 7] + 12 * (d // 7))
    return notes


def music(track_id, seed):
    key, mode, bpm, bpb, prog, flavour = MUSIC[track_id]
    rng = np.random.default_rng(seed)
    scale = MAJOR if mode == 'major' else MINOR
    root = 48 + NOTE[key]
    beat = 60.0 / bpm
    bar = beat * bpb
    bars_per_chord = 1 if flavour in ('battle', 'waltz') else 2
    reps = 2 if flavour in ('battle', 'waltz') else 1
    total = bar * bars_per_chord * len(prog) * reps
    n = int(round(total * SR))
    pads, lead, low, perc = (np.zeros(n) for _ in range(4))
    melody_rng = np.random.default_rng(seed + 1)
    for r in range(reps):
        for ci, degree in enumerate(prog):
            start = (r * len(prog) + ci) * bar * bars_per_chord
            dur = bar * bars_per_chord
            notes = chord(root, scale, degree)
            if flavour not in ('battle',):
                for m in notes:
                    place_wrap(pads, pad(hz(m + 12), dur + 1.0, rng) * 0.22, start)
            place_wrap(low, tone(hz(notes[0] - 12), dur, ((1, 1.0), (2, 0.35), (3, 0.1)))
                       * env_adsr(int(dur * SR), 0.05, 0.3, 0.7, 0.3) * 0.35, start)
            steps = int(round(dur / (beat / 2)))
            arp = notes + [notes[0] + 12, notes[1] + 12]
            for s in range(steps):
                at = start + s * beat / 2
                if flavour in ('guitar_celesta', 'harp', 'village'):
                    m = arp[[0, 1, 2, 3, 2, 1, 4, 2][s % 8]] + 12
                    place_wrap(lead, pluck(hz(m), 1.4, 1.2 if flavour == 'village' else 0.8) * 0.28, at)
                    if flavour == 'guitar_celesta' and s % 4 == 0 and melody_rng.random() < 0.6:
                        m2 = root + 24 + scale[melody_rng.integers(0, 7)]
                        place_wrap(lead, tone(hz(m2), 1.5, ((1, 1), (4, 0.2)), decay=0.5) * 0.12, at)
                elif flavour == 'glass':
                    if s % 3 == 0:
                        m = arp[melody_rng.integers(0, 5)] + 24
                        place_wrap(lead, tone(hz(m), 2.5, ((1, 1), (2.76, 0.15)), decay=0.9) * 0.14, at)
                elif flavour == 'cello':
                    if s % 4 == 0:
                        m = arp[melody_rng.integers(0, 4)] + 12
                        place_wrap(lead, pluck(hz(m), 2.0, 0.5) * 0.2, at)
                elif flavour == 'musicbox':
                    if s % 2 == 0 and melody_rng.random() < 0.7:
                        m = arp[melody_rng.integers(0, 5)] + 24
                        place_wrap(lead, tone(hz(m), 1.8, ((1, 1), (3, 0.3), (5.4, 0.1)), decay=0.45) * 0.16, at)
                elif flavour == 'battle':
                    m = arp[[0, 0, 2, 0, 1, 0, 3, 2][s % 8]]
                    place_wrap(lead, pluck(hz(m + 12), 0.35, 1.4) * 0.3, at)
                    if s % 2 == 0:
                        place_wrap(perc, kick(rng) * (0.8 if s % 4 == 0 else 0.4), at)
                    if s % 4 == 2:
                        place_wrap(perc, drum(rng, 150, 1200, 0.12) * 0.5, at)
                    place_wrap(perc, shaker(rng) * 0.5, at)
                elif flavour == 'waltz':
                    # oom-pah-pah on quarter notes, harpsichord-like plucks
                    if s % 2 == 0:
                        q = (s // 2) % bpb
                        if q == 0:
                            place_wrap(low, pluck(hz(notes[0] - 12), 0.6, 0.6) * 0.5, at)
                            place_wrap(perc, kick(rng) * 0.5, at)
                        else:
                            for m in notes[1:]:
                                place_wrap(lead, pluck(hz(m + 12), 0.4, 2.0) * 0.16, at)
                    elif melody_rng.random() < 0.5:
                        place_wrap(lead, pluck(hz(arp[melody_rng.integers(0, 5)] + 24), 0.5, 2.0) * 0.12, at)
            if flavour == 'village':
                for b in range(bars_per_chord * bpb):
                    place_wrap(perc, drum(rng, 200, 900, 0.08) * (0.25 if b % 2 == 0 else 0.12), start + b * beat)
            if flavour == 'waltz' and ci % 2 == 0:
                place_wrap(perc, bell_voice(hz(root - 12 + 7), 4.0) * 0.12, start)
    mix = pads + lead + low + perc
    ir_l, ir_r = reverb_ir(2.2, rng), reverb_ir(2.2, rng)
    wet = 0.5 if flavour not in ('battle',) else 0.25
    left = mix + wet * circular_reverb(mix, ir_l)
    right = mix + wet * circular_reverb(mix, ir_r)
    st = np.stack([left, right], axis=1)
    return norm(st, 0.8)


# --- Stings and effects ----------------------------------------------------------------------------


def sting(kind, rng):
    out = np.zeros(int(5 * SR))
    if kind == 'victory':
        root = 62
        for i, m in enumerate([0, 4, 7, 12, 16]):
            place(out, pluck(hz(root + m), 1.2, 1.0) * 0.3, i * 0.11)
        for m in (0, 4, 7, 12):
            place(out, pad(hz(root + m), 3.6, rng) * 0.3, 0.6)
    else:
        root = 50
        for i, m in enumerate([7, 3, 2, 0]):
            place(out, tone(hz(root + m), 1.2, ((1, 1), (2, 0.4), (3, 0.2))) * env_adsr(int(1.2 * SR), 0.08, 0.2, 0.7, 0.5)
                  * 0.3, i * 0.45)
        for m in (-12, 0, 3, 7):
            place(out, pad(hz(root + m), 3.0, rng) * 0.3, 1.7)
    return norm(linear_reverb(out, reverb_ir(1.6, rng), 0)[:len(out)] * 0.6 + out)


def sweep(f0, f1, seconds, partials=((1, 1.0),), curve=1.0):
    t = t_axis(seconds)
    f = f0 + (f1 - f0) * (t / seconds) ** curve
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin(ph * m) for m, a in partials)


def sfx(sid, rng):
    if sid == 'zoltraak_cast':
        s = sweep(400, 1800, 0.5, ((1, 1), (2, 0.4), (3, 0.2)), 2) * env_adsr(int(0.5 * SR), 0.3, 0.1, 0.8, 0.05)
        z = highpass(noise(0.4, rng), 3000) * np.exp(-t_axis(0.4) / 0.08) + sweep(1800, 900, 0.4) * np.exp(
            -t_axis(0.4) / 0.1)
        return np.concatenate([s * 0.5, z * 0.8])
    if sid == 'zoltraak_impact':
        n = bandpass(noise(0.8, rng), 800, 8000) * np.exp(-t_axis(0.8) / 0.08)
        place(n, kick(rng) * 0.8, 0)
        return n + tone(1600, 0.8, ((1, 1), (1.5, 0.5)), decay=0.15) * 0.3
    if sid == 'salve_cast':
        out = np.zeros(int(1.3 * SR))
        for i in range(5):
            z = sweep(1500 + 150 * i, 600, 0.25, ((1, 1), (2, 0.3))) * np.exp(-t_axis(0.25) / 0.07)
            place(out, z * 0.6 + highpass(noise(0.25, rng), 4000) * np.exp(-t_axis(0.25) / 0.03) * 0.4, i * 0.14)
        return out
    if sid == 'barrier_up':
        t = t_axis(1.4)
        s = sweep(300, 600, 1.4, ((1, 1), (2, 0.5), (3, 0.3), (5, 0.1))) * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
        return s * env_adsr(len(t), 0.4, 0.3, 0.6, 0.6) + tone(2400, 1.4, ((1, 1), (1.33, 0.6)), decay=0.4) * 0.15
    if sid == 'barrier_break':
        out = highpass(noise(1.4, rng), 2500) * np.exp(-t_axis(1.4) / 0.05) * 1.2
        for i in range(14):
            place(out, tone(rng.uniform(2500, 6500), 0.3, ((1, 1),), decay=0.06) * 0.3, rng.uniform(0.02, 1.0))
        return out
    if sid == 'ultimate':
        t = t_axis(3.0)
        charge = sweep(80, 600, 1.4, ((1, 1), (2, 0.5), (3, 0.3)), 1.5) * np.linspace(0.1, 1, int(1.4 * SR))
        blast = (lowpass(noise(1.6, rng), 2500) * 0.8 + sweep(900, 200, 1.6, ((1, 1), (2, 0.5))) * 0.5) * np.exp(
            -t_axis(1.6) / 0.5)
        out = np.concatenate([charge * 0.5, blast])
        place(out, kick(rng) * 1.2, 1.4)
        return out[:len(t)]
    if sid == 'hit_flesh':
        return lowpass(noise(0.3, rng), 900) * np.exp(-t_axis(0.3) / 0.04) * 1.5 + kick(rng)[:int(0.3 * SR)] * 0.6
    if sid == 'hit_stone':
        n = bandpass(noise(0.5, rng), 600, 6000) * np.exp(-t_axis(0.5) / 0.05)
        for i in range(6):
            place(n, bandpass(noise(0.05, rng), 1500, 5000) * np.exp(-t_axis(0.05) / 0.01) * 0.5, 0.03 + i * 0.04)
        return n + tone(160, 0.5, ((1, 1), (2.3, 0.5)), decay=0.07) * 0.6
    if sid == 'enemy_telegraph':
        t = t_axis(1.5)
        s = sweep(110, 220, 1.5, ((1, 1), (1.06, 0.8), (2, 0.4)), 1.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * t))
        return s * env_adsr(len(t), 0.2, 0.1, 1.0, 0.2)
    if sid == 'ash_seal':
        t = t_axis(2.0)
        thud = kick(rng) * 1.5
        crack = bandpass(noise(2.0, rng), 300, 4000) * np.exp(-t / 0.6) * (rng.random(len(t)) < 0.004) * 6
        hiss = highpass(noise(2.0, rng), 3000) * env_adsr(len(t), 0.05, 0.3, 0.3, 1.0) * 0.25
        out = crack + hiss + tone(55, 2.0, ((1, 1), (1.5, 0.5)), decay=0.7) * 0.6
        place(out, thud, 0.0)
        return out
    if sid == 'wolf_howl':
        t = t_axis(3.0)
        f = 420 + 160 * np.sin(np.pi * np.clip(t / 2.6, 0, 1)) - 60 * (t / 3.0)
        f = f * (1 + 0.01 * np.sin(2 * np.pi * 5 * t))
        ph = 2 * np.pi * np.cumsum(f) / SR
        s = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
        s += bandpass(noise(3.0, rng), 500, 2000) * 0.08
        out = s * env_adsr(len(t), 0.5, 0.2, 0.9, 1.0)
        return linear_reverb(out, reverb_ir(1.5, rng), 0)[:len(out)] * 0.5 + out * 0.7
    if sid == 'lantern_blaze':
        t = t_axis(2.0)
        whoosh = bandpass(noise(2.0, rng), 200, 3000) * env_adsr(len(t), 0.15, 0.3, 0.5, 1.0)
        crackle = highpass(noise(2.0, rng), 2000) * (rng.random(len(t)) < 0.003) * 4
        ghost = tone(330, 2.0, ((1, 1), (1.5, 0.4)), decay=0.8) * (1 + 0.3 * np.sin(2 * np.pi * 4 * t)) * 0.2
        return whoosh + crackle + ghost
    if sid == 'level_up':
        out = np.zeros(int(2.5 * SR))
        for i, m in enumerate([72, 76, 79, 84, 88]):
            place(out, bell_voice(hz(m), 1.8) * 0.18, i * 0.09)
            place(out, pluck(hz(m), 1.2) * 0.2, i * 0.09)
        return out
    if sid == 'loot_common':
        out = lowpass(noise(0.3, rng), 1500) * np.exp(-t_axis(0.3) / 0.05) * 0.5
        place(out, tone(2600, 0.3, ((1, 1), (2.4, 0.4)), decay=0.06) * 0.4, 0.08)
        return np.concatenate([out, np.zeros(int(0.5 * SR))])
    if sid == 'loot_rare':
        out = np.zeros(int(1.8 * SR))
        for i in range(10):
            place(out, tone(hz(84 + [0, 4, 7, 11, 12, 16, 19, 23, 24, 28][i]), 0.8, ((1, 1),), decay=0.2) * 0.2,
                  i * 0.05)
        place(out, bell_voice(hz(84), 1.6) * 0.15, 0)
        return out
    if sid == 'ui_click':
        return tone(1800, 0.06, ((1, 1), (2.7, 0.3)), decay=0.012) + bandpass(noise(0.06, rng), 1000, 4000) * np.exp(
            -t_axis(0.06) / 0.005) * 0.4
    if sid == 'ui_confirm':
        out = np.zeros(int(0.45 * SR))
        place(out, tone(hz(79), 0.3, ((1, 1), (2, 0.2)), decay=0.08), 0)
        place(out, tone(hz(84), 0.35, ((1, 1), (2, 0.2)), decay=0.1), 0.08)
        return out
    if sid == 'ui_back':
        out = bandpass(noise(0.15, rng), 1500, 6000) * env_adsr(int(0.15 * SR), 0.03, 0.05, 0.4, 0.05) * 0.4
        place(out, tone(hz(67), 0.15, ((1, 1),), decay=0.04) * 0.6, 0.04)
        return out
    if sid == 'chest_open':
        t = t_axis(1.6)
        creak = sweep(180, 260, 0.9, ((1, 1), (2, 0.6), (3, 0.4), (4, 0.3))) * (
            0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t_axis(0.9)))) * 0.25
        out = np.zeros(len(t))
        place(out, creak * env_adsr(len(creak), 0.1, 0.1, 0.8, 0.2), 0)
        place(out, lowpass(noise(0.3, rng), 600) * np.exp(-t_axis(0.3) / 0.05) * 1.2, 0.85)
        place(out, tone(hz(88), 0.6, ((1, 1),), decay=0.2) * 0.12, 1.0)
        return out
    if sid == 'gate_open':
        t = t_axis(2.0)
        rattle = bandpass(noise(2.0, rng), 1500, 7000) * (np.sin(2 * np.pi * 18 * t) > 0.6) * 0.6
        grind = bandpass(noise(2.0, rng), 100, 600) * 0.6
        return (rattle + grind) * env_adsr(len(t), 0.1, 0.1, 1.0, 0.4) + tone(90, 2.0, ((1, 1), (2.7, 0.3))) * 0.1
    if sid == 'interrupt':
        return np.concatenate([highpass(noise(0.05, rng), 2000) * 1.2,
                               sweep(2000, 400, 0.25, ((1, 1), (1.5, 0.4))) * np.exp(-t_axis(0.25) / 0.05)])
    if sid == 'bell':
        out = bell_voice(hz(43), 9.0, rng, 0.8)  # low G, about 98 Hz
        return linear_reverb(out, reverb_ir(3.0, rng, 3000), 0)[:len(out)] * 0.5 + out
    raise KeyError(sid)


def steps(surface, rng, count=4):
    out = []
    for i in range(count):
        if surface == 'grass':
            n = highpass(noise(0.25, rng), 1500) * (rng.random(int(0.25 * SR)) < 0.08) * 1.5
            s = n * np.exp(-t_axis(0.25) / 0.06) + lowpass(noise(0.25, rng), 400) * np.exp(-t_axis(0.25) / 0.03) * 0.5
        elif surface == 'stone':
            s = bandpass(noise(0.2, rng), 1500, 7000) * np.exp(-t_axis(0.2) / 0.012) * 0.8
            s += tone(rng.uniform(90, 130), 0.2, ((1, 1),), decay=0.025) * 0.6
        else:
            s = tone(rng.uniform(170, 210), 0.25, ((1, 1), (2.3, 0.4), (3.9, 0.2)), decay=0.05) * 0.7
            s += bandpass(noise(0.25, rng), 400, 3000) * np.exp(-t_axis(0.25) / 0.015) * 0.5
        out.append(s)
    return out


def loop_ambience(sid, rng, seconds=12.0):
    n = int(seconds * SR)
    out = np.zeros(n)
    if sid == 'amb_fountain':
        out += bandpass(noise(seconds, rng), 400, 6000) * 0.12
        for _ in range(int(seconds * 25)):
            drop = tone(rng.uniform(500, 2200), 0.08, ((1, 1),), decay=0.015) * rng.uniform(0.05, 0.25)
            place_wrap(out, drop, rng.uniform(0, seconds))
    else:
        out += lowpass(noise(seconds, rng), 500) * 0.15
        for _ in range(int(seconds * 9)):
            pop = bandpass(noise(0.04, rng), 1000, 8000) * np.exp(-t_axis(0.04) / 0.006) * rng.uniform(0.2, 1.0)
            place_wrap(out, pop, rng.uniform(0, seconds))
    return out


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'art/source/audio/placeholder')
    os.makedirs(out_dir, exist_ok=True)
    plan = json.load(open(os.path.join(ROOT, 'art/source/audio/plan.json')))
    for k, item in enumerate(plan['items']):
        sid = item['id']
        rng = np.random.default_rng(9000 + k)
        if item['kind'] == 'music':
            data = music(sid, 9000 + k)
        elif item['kind'] == 'sting':
            data = sting(sid.split('_', 1)[1], rng)
        elif item['kind'] == 'loop':
            data = loop_ambience(sid, rng)
        elif sid.startswith('steps_'):
            for i, s in enumerate(steps(sid.split('_', 1)[1], rng)):
                wavfile.write(os.path.join(out_dir, f'{sid}_{i + 1}.wav'), SR, norm(s, 0.9).astype(np.float32))
            print(sid, '4 variants')
            continue
        else:
            data = sfx(sid, rng)
        data = norm(data, 0.9).astype(np.float32)
        wavfile.write(os.path.join(out_dir, sid + '.wav'), SR, data)
        print(sid, f'{len(data) / SR:.1f} s')


if __name__ == '__main__':
    main()
