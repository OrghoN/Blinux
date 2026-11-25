"""Offline speech-to-text, to check *what* the guest said, not just that it spoke.

Uses Vosk's small English model (about 40 MB), cached in ~/.cache/blinux-stt
(CI caches that directory). eSpeak NG's robotic voice transcribes imperfectly,
so tests look for a few distinctive words rather than exact sentences.
"""

from __future__ import annotations

import json
import os
import urllib.request
import wave
import zipfile

MODEL_NAME = "vosk-model-small-en-us-0.15"
MODEL_URL = f"https://alphacephei.com/vosk/models/{MODEL_NAME}.zip"
CACHE = os.path.expanduser(os.environ.get("BLINUX_STT_CACHE", "~/.cache/blinux-stt"))


def model_path() -> str:
    path = os.path.join(CACHE, MODEL_NAME)
    if not os.path.isdir(path):
        os.makedirs(CACHE, exist_ok=True)
        archive = os.path.join(CACHE, MODEL_NAME + ".zip")
        urllib.request.urlretrieve(MODEL_URL, archive)
        with zipfile.ZipFile(archive) as z:
            z.extractall(CACHE)
        os.remove(archive)
    return path


def transcribe(wav_path: str) -> str:
    from vosk import KaldiRecognizer, Model, SetLogLevel

    SetLogLevel(-1)
    model = Model(model_path())
    with wave.open(wav_path, "rb") as w:
        rec = KaldiRecognizer(model, w.getframerate())
        words = []
        while True:
            data = w.readframes(4000)
            if not data:
                break
            if rec.AcceptWaveform(data):
                words.append(json.loads(rec.Result()).get("text", ""))
        words.append(json.loads(rec.FinalResult()).get("text", ""))
    return " ".join(w for w in words if w).lower()


def heard_any(text: str, *words: str) -> bool:
    return any(w.lower() in text for w in words)
