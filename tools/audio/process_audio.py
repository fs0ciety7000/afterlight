#!/usr/bin/env python3
"""Turns the audio sources into game files: assets/audio/music/<id>.ogg and assets/audio/sfx/<id>.ogg.

Source per id of art/source/audio/plan.json: the fal output art/source/audio/raw/<id>.* when it exists, else the
synthesised placeholder art/source/audio/placeholder/<id>.wav (tools/audio/synth_placeholders.py).
Steps: fal music gets a loop (trimmed tail, crossfade of the end into the start); footsteps from fal are cut
into 4 single steps; loudness is set by measured EBU R128 loudness (ffmpeg ebur128) with a peak ceiling;
SFX are mono; everything is encoded to Ogg Vorbis. A report goes to art/source/audio/processed.json.

  python3 tools/audio/process_audio.py [id...]
"""
import glob
import json
import os
import re
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'art/source/audio')
OUT = os.path.join(ROOT, 'assets/audio')
## Target integrated loudness (LUFS) per kind, and the sample-peak ceiling (dBFS).
TARGET = {'music': -18.0, 'sting': -16.0, 'sfx': -14.0, 'ui': -20.0, 'loop': -24.0}
PEAK_DB = -1.0
QUALITY = {'music': 0, 'sting': 3, 'sfx': 3, 'ui': 3, 'loop': 2}
LOOP_XFADE_S = 2.0
## Loop taken from the fal take: start (past the intro) and length range, seconds (export size budget).
LOOP_START_S = 6.0
LOOP_LENGTH_S = (52.0, 66.0)
STEP_COUNT = 4
STEP_DECAY_S = 0.07
## Longest kept length (s) for takes that repeat their sound (the click take holds several clicks).
MAX_S = {'ui_click': 0.09}


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def encode(x, path, quality):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    channels = 1 if x.ndim == 1 else x.shape[1]
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ac', str(channels), '-ar', str(SR), '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', str(quality), '-map_metadata', '-1', path],
                   input=x.astype(np.float32).tobytes(), check=True)


def lufs(x):
    """Integrated loudness via ffmpeg's ebur128 (short sounds are padded with silence, which the gate drops)."""
    pad = max(0, SR - len(x))
    y = np.concatenate([x, np.zeros((pad,) + x.shape[1:])]) if pad else x
    channels = 1 if y.ndim == 1 else y.shape[1]
    r = subprocess.run(['ffmpeg', '-v', 'info', '-nostats', '-f', 'f32le', '-ac', str(channels), '-ar', str(SR),
                        '-i', '-', '-af', 'ebur128', '-f', 'null', '-'],
                       input=y.astype(np.float32).tobytes(), capture_output=True)
    m = re.findall(r'I:\s+(-?[\d.]+|-inf) LUFS', r.stderr.decode())
    return float(m[-1]) if m and m[-1] != '-inf' else -70.0


def normalise(x, target):
    gain_db = target - lufs(x)
    peak = np.max(np.abs(x)) or 1.0
    gain_db = min(gain_db, PEAK_DB - 20 * np.log10(peak))  # peak-safe
    return x * 10 ** (gain_db / 20), gain_db


def _features(mono, hop):
    """Log band energies per frame (coarse spectrum), to compare two moments of a track."""
    n = len(mono) // hop
    frames = mono[:n * hop].reshape(n, hop) * np.hanning(hop)
    spec = np.abs(np.fft.rfft(frames, axis=1))
    edges = np.unique(np.geomspace(2, spec.shape[1] - 1, 25).astype(int))
    bands = np.stack([spec[:, a:b].sum(axis=1) for a, b in zip(edges[:-1], edges[1:])], axis=1)
    f = np.log(bands + 1e-6)
    return (f - f.mean(axis=1, keepdims=True)) / (f.std(axis=1, keepdims=True) + 1e-6)


def find_loop(x, start_s=LOOP_START_S, length_s=LOOP_LENGTH_S, window_s=4.0, tail_s=6.0):
    """Start and length (samples) of the loop: the length near `length_s` whose next seconds sound most like
    the start (spectral match), then aligned to the sample by cross-correlation at the seam."""
    mono = x.mean(axis=1)
    hop = int(0.05 * SR)
    f = _features(mono, hop)
    usable_s = len(x) / SR - tail_s - LOOP_XFADE_S
    hi_s = min(length_s[1], usable_s - start_s)
    a = int(start_s * SR / hop)
    w = int(window_s * SR / hop)
    best, best_len = -1e9, None
    for L in range(int(length_s[0] * SR / hop), int(hi_s * SR / hop)):
        if a + L + w >= len(f):
            break
        score = float(np.mean(f[a:a + w] * f[a + L:a + L + w]))
        if score > best:
            best, best_len = score, L
    if best_len is None:  # short take: the whole usable part
        return int(start_s * SR), int((usable_s - start_s) * SR), 0.0
    s0, L = a * hop, best_len * hop
    r = int(0.03 * SR)  # sample alignment within +-30 ms
    ref = mono[s0:s0 + int(0.2 * SR)]
    seg = mono[s0 + L - r:s0 + L + r + len(ref)]
    shift = int(np.argmax(np.correlate(seg, ref, 'valid'))) - r
    return s0, L + shift, best


def make_loop(x, xfade_s=LOOP_XFADE_S):
    """fal music: a loop of about a minute taken past the intro and before the ending, its end crossfaded into
    its start (equal power) so the wrap is seamless."""
    s0, L, score = find_loop(x)
    c = int(xfade_s * SR)
    y = x[s0:s0 + L + c]
    body = y[c:].copy()
    ramp = np.linspace(0, 1, c)[:, None]
    body[-c:] = y[-c:] * np.cos(ramp * np.pi / 2) + y[:c] * np.sin(ramp * np.pi / 2)
    return body, {'loop_start_s': round(s0 / SR + xfade_s, 2), 'loop_match': round(score, 3)}


def trim_silence(x, threshold_db=-50.0, keep_s=0.01):
    env = np.abs(x if x.ndim == 1 else x.max(axis=1))
    above = np.where(env > 10 ** (threshold_db / 20))[0]
    if len(above) == 0:
        return x
    a = max(0, above[0] - int(keep_s * SR))
    b = min(len(x), above[-1] + int(0.05 * SR))
    y = x[a:b].copy()
    fade = min(len(y), int(0.01 * SR))
    y[-fade:] *= np.linspace(1, 0, fade) if y.ndim == 1 else np.linspace(1, 0, fade)[:, None]
    return y


def split_steps(x, count=STEP_COUNT):
    """Cuts a take of several footsteps into single steps at the loudest onsets."""
    win = int(0.01 * SR)
    env = np.convolve(np.abs(x), np.ones(win) / win, 'same')
    min_gap = int(0.18 * SR)
    order = np.argsort(env)[::-1]
    picks = []
    for i in order:
        if all(abs(i - p) > min_gap for p in picks):
            picks.append(i)
        if len(picks) == count:
            break
    out = []
    for p in sorted(picks):
        a = max(0, p - int(0.03 * SR))
        take = x[a:a + int(0.35 * SR)].copy()
        # Decay from the step's peak: keeps the footfall, drops the rustle and noise floor around it.
        peak = int(np.argmax(np.abs(take)))
        env = np.ones(len(take))
        env[peak:] = np.exp(-np.arange(len(take) - peak) / (STEP_DECAY_S * SR))
        out.append(trim_silence(take * env))
    return out


def source_of(item_id):
    raw = sorted(glob.glob(os.path.join(SRC, 'raw', item_id + '.*')))
    if raw:
        return raw[0], 'fal'
    return os.path.join(SRC, 'placeholder', item_id + '.wav'), 'placeholder'


def kind_of(item):
    return 'ui' if item['id'].startswith('ui_') else item['kind']


def process(item, report):
    kind = kind_of(item)
    path, origin = source_of(item['id'])
    folder = 'music' if kind in ('music', 'sting') else 'sfx'
    if item['id'].startswith('steps_'):
        if origin == 'fal':
            takes = split_steps(decode(path).mean(axis=1))
        else:
            takes = [decode(p).mean(axis=1) for p in
                     sorted(glob.glob(os.path.join(SRC, 'placeholder', item['id'] + '_*.wav')))]
        for i, take in enumerate(takes):
            sid = f'{item["id"]}_{i + 1}'
            y, gain = normalise(take, TARGET['sfx'] - 4.0)  # steps sit under the action
            dest = os.path.join(OUT, 'sfx', sid + '.ogg')
            encode(y, dest, QUALITY['sfx'])
            report[sid] = entry(dest, origin, y, gain)
        return
    if not os.path.exists(path):
        print('missing source', item['id'])
        return
    x = decode(path)
    extra = {}
    if kind == 'music':
        if origin == 'fal':
            x, extra = make_loop(x)
    elif kind == 'loop':
        x = x.mean(axis=1)  # fal `loop: true` and placeholders are already seamless
    else:
        x = trim_silence(x.mean(axis=1) if kind != 'sting' else x)
        if item['id'] in MAX_S:
            x = x[:int(MAX_S[item['id']] * SR)].copy()
            fade = int(0.02 * SR)
            x[-fade:] *= np.linspace(1, 0, fade)
    y, gain = normalise(x, TARGET[kind])
    dest = os.path.join(OUT, folder, item['id'] + '.ogg')
    encode(y, dest, QUALITY[kind])
    report[item['id']] = entry(dest, origin, y, gain) | extra


def entry(dest, origin, y, gain):
    return {'file': os.path.relpath(dest, ROOT), 'origin': origin, 'seconds': round(len(y) / SR, 2),
            'channels': 1 if y.ndim == 1 else y.shape[1], 'gain_db': round(float(gain), 1),
            'bytes': os.path.getsize(dest)}


def main():
    plan = json.load(open(os.path.join(SRC, 'plan.json')))
    report_path = os.path.join(SRC, 'processed.json')
    report = json.load(open(report_path)) if os.path.exists(report_path) else {}
    only = set(sys.argv[1:])
    for item in plan['items']:
        if only and item['id'] not in only:
            continue
        process(item, report)
    with open(report_path, 'w') as f:
        json.dump(dict(sorted(report.items())), f, indent=1)
    total = sum(v['bytes'] for v in report.values())
    print(f'{len(report)} files, {total / 1e6:.2f} MB')


if __name__ == '__main__':
    main()
