"""Layer 4: the live ISO talks from the first second, with no key pressed."""

import os
import time

import pytest

from harness import audio, stt
from harness.vm import VM


def test_default_boot_speaks(iso, artifacts, firmware):
    """Boot the unmodified ISO and press nothing: the default entry must be the
    speech one, and the welcome message must be read aloud."""
    vm = VM(f"live-default-{firmware}", artifacts, firmware=firmware, iso=iso)
    with vm:
        # Boot menu timeout (5 s) + kernel + espeakup + motd.
        time.sleep(150)
    speech = audio.analyse(vm.wav)
    assert speech.first_sound is not None, "the live medium never made a sound"
    assert speech.voiced_seconds > 3, f"only {speech.voiced_seconds:.1f}s of sound"
    heard = stt.transcribe(vm.wav)
    with open(os.path.join(artifacts, f"{vm.name}.txt"), "w") as fh:
        fh.write(heard)
    assert stt.heard_any(heard, "install", "welcome", "linux"), f"heard: {heard!r}"


@pytest.fixture
def live(iso, artifacts, live_kernel, firmware):
    vm = VM(f"live-serial-{firmware}", artifacts, firmware=firmware, iso=iso, kernel=live_kernel)
    with vm:
        vm.login("root")
        yield vm


def test_live_environment(live):
    assert live.sh("systemctl is-active espeakup.service") == "active"
    assert "blinux-install" in live.sh("blinux-install --help")
    assert live.sh("test -f /opt/blinux/offline-repo/blinux-offline.db && echo yes") == "yes"
    assert "blinux-base" in live.sh("tar -tf /opt/blinux/offline-repo/blinux-offline.db.tar.zst | "
                                    "grep -m1 blinux-base")
    # The installer's dry run works on the real live system.
    out = live.sh("blinux-install --dry-run --config /dev/stdin <<'EOF'\n"
                  '{"disk": "/dev/vda", "username": "t", "password": "p"}\nEOF')
    assert "Installation complete." in out
