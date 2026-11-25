"""Find speech in the WAV files QEMU records from the guest's sound card.

QEMU is started with
    -audiodev wav,id=snd0,path=X.wav,out.frequency=16000,out.channels=1,out.format=s16
    -device intel-hda -device hda-duplex,audiodev=snd0
so every sample the guest plays lands in X.wav as 16 kHz mono 16-bit PCM,
which is also what the speech-to-text model wants.
"""

from __future__ import annotations

import array
import math
import wave
from dataclasses import dataclass

WINDOW_SECONDS = 0.05
# RMS (of 16-bit samples) above this counts as sound. Speech from espeak-ng at
# default volume is in the thousands; a silent stream is near zero.
THRESHOLD = 300


@dataclass
class Speech:
    voiced_seconds: float  # total time with sound
    first_sound: float | None  # seconds from the start of the file
    longest_gap: float  # longest silence between the first and last sound
    duration: float


def analyse(path: str, threshold: int = THRESHOLD) -> Speech:
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2:
            raise ValueError(f"{path}: expected 16-bit samples")
        rate, channels = w.getframerate(), w.getnchannels()
        frames = w.readframes(w.getnframes())
    samples = array.array("h", frames)
    if channels > 1:
        samples = samples[::channels]
    step = max(1, int(rate * WINDOW_SECONDS))
    voiced, first, last, gap, longest = 0, None, None, 0.0, 0.0
    for i in range(0, len(samples), step):
        chunk = samples[i : i + step]
        if not chunk:
            break
        rms = math.sqrt(sum(s * s for s in chunk) / len(chunk))
        t = i / rate
        if rms > threshold:
            voiced += 1
            if first is None:
                first = t
            if last is not None:
                longest = max(longest, gap)
            gap = 0.0
            last = t
        elif first is not None:
            gap += WINDOW_SECONDS
    return Speech(voiced * WINDOW_SECONDS, first, longest, len(samples) / rate)


def tail(path: str, start_seconds: float, out_path: str) -> str:
    """Copy the part of PATH after START_SECONDS into OUT_PATH."""
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        w.setpos(min(int(start_seconds * rate), w.getnframes()))
        frames = w.readframes(w.getnframes())
        params = w.getparams()
    with wave.open(out_path, "wb") as o:
        o.setparams(params)
        o.writeframes(frames)
    return out_path


def duration(path: str) -> float:
    with wave.open(path, "rb") as w:
        return w.getnframes() / w.getframerate()
