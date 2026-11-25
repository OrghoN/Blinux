"""Fast checks of the speech detector itself (no VM needed)."""

import array
import math
import wave

from harness import audio


def make_wav(path, segments, rate=16000):
    samples = array.array("h")
    for kind, seconds in segments:
        n = int(seconds * rate)
        if kind == "tone":
            samples.extend(int(8000 * math.sin(2 * math.pi * 440 * i / rate)) for i in range(n))
        else:
            samples.extend([0] * n)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(samples.tobytes())
    return str(path)


def test_finds_speech_and_gaps(tmp_path):
    wav = make_wav(tmp_path / "t.wav", [("sil", 2), ("tone", 1.5), ("sil", 3), ("tone", 1)])
    s = audio.analyse(wav)
    assert abs(s.first_sound - 2.0) < 0.06
    assert abs(s.voiced_seconds - 2.5) < 0.1
    assert abs(s.longest_gap - 3.0) < 0.1


def test_silence_is_silent(tmp_path):
    s = audio.analyse(make_wav(tmp_path / "s.wav", [("sil", 3)]))
    assert s.first_sound is None and s.voiced_seconds == 0


def test_tail(tmp_path):
    wav = make_wav(tmp_path / "t.wav", [("sil", 2), ("tone", 1.5), ("sil", 3), ("tone", 1)])
    s = audio.analyse(audio.tail(wav, 4, str(tmp_path / "tail.wav")))
    assert abs(s.voiced_seconds - 1.0) < 0.1
