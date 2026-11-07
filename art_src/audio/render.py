"""Render eatvenLike's original score and cues. Requires NumPy, SciPy, FFmpeg."""
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "art/audio"

# Each bar carries bass, three upper chord tones, and hand-scored melody
# (beat, MIDI note, duration in beats). The two shops share the opening motif.
SCORE = [
    (48, (60, 64, 67), ((0, 76, .65), (1, 79, .42), (1.5, 81, .4), (2.5, 79, .85))),
    (47, (59, 62, 67), ((.5, 74, .65), (1.5, 76, .4), (2, 79, 1.35))),
    (45, (60, 64, 69), ((0, 76, .5), (1, 72, .4), (1.5, 74, .4), (2.5, 76, .9))),
    (41, (60, 64, 69), ((.5, 77, .6), (1.5, 76, .45), (2.5, 72, 1))),
    (50, (60, 65, 69), ((0, 74, .65), (1, 77, .45), (2, 81, .8), (3.25, 79, .4))),
    (43, (59, 62, 67), ((0, 79, .65), (1, 74, .45), (2, 71, .9))),
    (48, (60, 64, 67), ((0, 72, 1), (1.5, 76, .5), (2.5, 79, .75))),
    (48, (64, 67, 69), ((.5, 76, 1.1), (2.5, 74, .5))),
    (45, (60, 64, 67), ((0, 72, .85), (1.5, 76, .45), (2, 79, .55), (3, 81, .6))),
    (40, (59, 62, 67), ((.5, 83, .65), (1.5, 79, .4), (2.5, 76, .85))),
    (41, (60, 64, 69), ((0, 81, .65), (1, 79, .4), (1.5, 77, .7), (3, 76, .45))),
    (48, (60, 64, 67), ((.5, 72, .75), (2, 74, .4), (2.5, 76, .65))),
    (50, (60, 65, 69), ((0, 77, .65), (1, 81, .7), (2.5, 84, .85))),
    (45, (60, 64, 69), ((.5, 81, .55), (1.5, 76, .5), (2.5, 72, .8))),
    (41, (60, 65, 69), ((0, 77, 1.05), (1.5, 76, .6), (2.5, 74, .6))),
    (43, (59, 62, 67), ((0, 71, .65), (1.5, 74, 1), (3, 79, .55))),
    (48, (60, 64, 67), ((0, 76, .65), (1, 79, .42), (1.5, 81, .4), (2.5, 84, .85))),
    (47, (59, 62, 67), ((.5, 83, .65), (1.5, 79, .4), (2.5, 74, .65))),
    (45, (60, 64, 69), ((0, 76, .5), (1, 72, .4), (1.5, 74, .4), (2.5, 76, .9))),
    (40, (59, 64, 67), ((.5, 79, .7), (2, 76, .8))),
    (41, (60, 65, 69), ((0, 77, .65), (1, 81, .45), (2, 79, .8), (3.25, 77, .4))),
    (43, (59, 62, 67), ((0, 76, .65), (1, 74, .45), (2, 71, .9))),
    (48, (60, 64, 67), ((0, 72, 1.25), (2, 67, .75))),
    (43, (59, 62, 67), ((.5, 71, .65), (2, 74, .55), (3, 67, .6))),
]


def note(midi, duration, voice):
    t = np.arange(round(RATE * duration)) / RATE
    phase = 2 * np.pi * 440 * 2 ** ((midi - 69) / 12) * t
    if voice == "wood":
        wave = np.sin(phase) * np.exp(-t * 6) + .18 * np.sin(phase * 3.99) * np.exp(-t * 28)
        wave += .055 * np.sin(phase * 9.02) * np.exp(-t * 53)
        attack = .007
    elif voice == "keys":
        wave = .86 * np.sin(phase + .65 * np.exp(-4 * t) * np.sin(phase * 2.006)) * np.exp(-t * 2.1)
        wave += .15 * np.sin(phase * 1.003) * np.exp(-t * 3.4)
        attack = .017
    elif voice == "bell":
        wave = .87 * np.sin(phase) * np.exp(-t * 5) + .16 * np.sin(phase * 2.78) * np.exp(-t * 13)
        wave += .052 * np.sin(phase * 5.09) * np.exp(-t * 25)
        attack = .005
    else:
        wave = .82 * np.sin(phase) * np.exp(-t * 2.8)
        for harmonic, gain in ((2, .24), (3, .12), (4, .068), (5, .025)):
            wave += gain * np.sin(phase * harmonic + .25) * np.exp(-t * (3 + harmonic * 2))
        attack = .011
    return wave * np.minimum(t / attack, 1) * np.clip((duration - t) / .065, 0, 1)


def brush(seconds, low, high, decay, rng):
    t = np.arange(round(RATE * seconds)) / RATE
    filt = butter(2, [low, high], "bandpass", fs=RATE, output="sos")
    return sosfilt(filt, rng.normal(size=t.size)) * np.minimum(t / .006, 1) * np.exp(-t * decay) * np.clip((seconds - t) / .02, 0, 1)


def place(track, seconds, sound, level, pan=0):
    start = round(seconds * RATE)
    if track.ndim == 2:
        pan_gains = np.sqrt([(1 - pan) * .5, (1 + pan) * .5])
        sound = sound[:, None] * pan_gains
    # Circular placement preserves note and ambience tails across the loop boundary.
    indices = (start + np.arange(len(sound))) % len(track)
    track[indices] += level * sound


def music(tea):
    beat = 60 / (84 if tea else 92)
    rng = np.random.default_rng(112 if tea else 109)
    track = np.zeros((round(beat * 4 * len(SCORE) * RATE), 2))
    lead = "keys" if tea else "wood"
    backing = "keys" if tea else "pluck"

    def add(at, midi, length, voice, gain, pan):
        timing = rng.uniform(.001, .017)
        place(track, at * beat + timing, note(midi, length * beat + .1, voice), gain * rng.uniform(.89, 1.1), pan)

    for bar, (bass, chord, melody) in enumerate(SCORE):
        start = bar * 4
        add(start, bass - 12, 1.45, "pluck", .18, -.11)
        add(start + 2.1, bass - 5 if bar not in (3, 10, 20) else bass, 1.05, "pluck", .11, -.07)
        if tea:
            for i, pitch in enumerate(chord):
                add(start + .34 + i * .12, pitch, 2.35 - i * .18, backing, .072, -.44 + i * .27)
                add(start + 2.77 + i * .10, pitch + (12 if i == 2 else 0), 1.05, backing, .035, -.38 + i * .3)
        else:
            for at, index in ((.48, 0), (1.0, 2), (1.51, 1), (2.25, 0), (3.03, 2), (3.52, 1)):
                add(start + at, chord[index], .54, backing, .083 if at < 2 else .065, -.37 + index * .23)
        for i, (at, pitch, length) in enumerate(melody):
            add(start + at, pitch if not tea else pitch - 12, length * (1.16 if tea else 1), lead, .20 if i == 0 else .159, .14)
            if tea and bar % 4 == 2 and i == 0:
                add(start + at + .13, pitch, length, "bell", .046, .49)
        if bar % 4 != 3:
            for at in ((1.5, 3.5) if tea else (1, 3, 3.75)):
                hit = brush(.13, 960, 4500, 37, rng)
                place(track, (start + at) * beat, hit, .048 if tea else .075, .38)
    dry = track.copy()
    for delay, level in ((.031, .11), (.073, .08), (.135, .057), (.228, .038)):
        track += np.roll(dry[:, ::-1], round(delay * RATE), axis=0) * level
    return track


def cues():
    rng = np.random.default_rng(27)
    specs = {
        "tap": (.145, [(0, 72, .14, "wood", .72)]),
        "sale": (.29, [(0, 81, .14, "bell", .38), (.052, 88, .23, "bell", .61)]),
        "upgrade": (.46, [(0, 69, .19, "wood", .73), (.085, 74, .25, "wood", .62), (.175, 81, .28, "bell", .55)]),
        "unlock": (.78, [(0, 65, .34, "pluck", .65), (.09, 72, .34, "wood", .63), (.18, 77, .52, "bell", .64), (.30, 81, .43, "bell", .38)]),
        "hire": (.54, [(0, 72, .24, "wood", .65), (.112, 76, .24, "wood", .57), (.20, 74, .34, "keys", .70)]),
        "flyers": (.36, [(.092, 76, .20, "wood", .44), (.163, 79, .19, "wood", .34)]),
        "complete": (1.85, [(0, 60, .65, "keys", .58), (0, 72, .55, "wood", .66),
            (.18, 76, .52, "wood", .60), (.36, 79, .51, "wood", .55),
            (.56, 65, .65, "keys", .56), (.59, 81, .55, "bell", .52),
            (.85, 79, .78, "bell", .49), (1.04, 72, .80, "keys", .47)]),
    }
    for name, (duration, score) in specs.items():
        track = np.zeros(round(RATE * duration))
        for start, pitch, length, voice, gain in score:
            place(track, start, note(pitch, length, voice), gain)
        if name == "flyers":
            place(track, .0, brush(.17, 550, 6100, 19, rng), .62)
            place(track, .057, brush(.24, 680, 3700, 18, rng), .47)
        yield name, track


def save_wav(path, track, level_db):
    signal = track * (10 ** (level_db / 20) / np.max(np.abs(track)))
    wavfile.write(path, RATE, (signal * 32767).round().astype(np.int16))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "music.wav"
        for name, tea in (("pancake_morning", False), ("milk_tea_afternoon", True)):
            save_wav(raw, music(tea), -3)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(raw),
                "-c:a", "libvorbis", "-q:a", "4", str(OUT / f"{name}.ogg")], check=True)
    for name, track in cues():
        save_wav(OUT / f"{name}.wav", track, -3)


if __name__ == "__main__":
    main()
