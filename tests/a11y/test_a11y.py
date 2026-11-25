"""Layer 5: accessibility inside the installed desktop.

Uses the minimal install (reusing tests/integration/artifacts/minimal.qcow2
from `make test-iso` when present), logs the test user into GNOME with a
test-only autologin, and checks AT-SPI, Orca's speech log, Emacspeak and
that no user action is met with silence.
"""

import json
import os
import subprocess
import time
import warnings

import pytest

from conftest import load_case
from harness import audio
from harness.install import TEST_PASSWORD, boot_installed, install_case

pytestmark = pytest.mark.a11y
GUEST = os.path.join(os.path.dirname(__file__), "..", "guest")


@pytest.fixture(scope="module")
def desktop(iso, live_kernel, artifacts):
    cfg = load_case("minimal")
    disk = os.path.join(artifacts, "minimal.qcow2")
    if os.path.exists(disk):
        copy = os.path.join(artifacts, "a11y.qcow2")
        subprocess.run(["qemu-img", "create", "-f", "qcow2", "-b", disk, "-F", "qcow2", copy],
                       check=True, capture_output=True)
        disk = copy
    else:
        disk = install_case("a11y", cfg, iso, live_kernel, artifacts)
    vm = boot_installed("a11y", cfg, disk, artifacts)
    try:
        vm.login(cfg["username"], TEST_PASSWORD, timeout=900)
        sudo = f"echo {TEST_PASSWORD} | sudo -S -p ''"
        vm.write_file("/tmp/custom.conf",
                      f"[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin={cfg['username']}")
        vm.sh(f"{sudo} install -m644 /tmp/custom.conf /etc/gdm/custom.conf")
        vm.sh(f"{sudo} systemctl restart gdm.service")
        deadline = time.monotonic() + 240
        while not vm.sh("pgrep -u $(id -u) -x orca >/dev/null && echo yes || true"):
            assert time.monotonic() < deadline, "the session never started Orca"
            time.sleep(5)
        # Talk to the graphical session from the serial shell.
        vm.sh("export $(tr '\\0' '\\n' < /proc/$(pgrep -u $(id -u) -x gnome-shell)/environ | "
              "grep -E '^(DBUS_SESSION_BUS_ADDRESS|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DISPLAY)=')")
        if vm.sh("python -c 'import gi' 2>/dev/null && echo yes || true") != "yes":
            vm.sh(f"{sudo} pacman -S --noconfirm --needed python-gobject", timeout=600)
        yield vm
    finally:
        vm.stop()


def type_text(vm, text):
    for ch in text:
        vm.send_keys({" ": "spc"}.get(ch, ch))
        time.sleep(0.1)


def test_atspi_tree(desktop):
    with open(os.path.join(GUEST, "a11y_check.py")) as fh:
        desktop.write_file("/tmp/a11y_check.py", fh.read())
    report = json.loads(desktop.sh("python /tmp/a11y_check.py", timeout=300).splitlines()[-1])
    assert report["shell"], "GNOME Shell isn't on the AT-SPI bus"
    for app, result in report["apps"].items():
        assert result["found"], f"{app} isn't exposed to AT-SPI"
        assert result["focusable"] > 0, f"{app} has no focusable widgets"
        if result["unnamed"]:
            warnings.warn(f"{app}: {len(result['unnamed'])} unnamed widgets: {result['unnamed'][:10]}")


def test_orca_speaks_focus_changes(desktop):
    desktop.sh("(orca --replace --debug-file=/tmp/orca-debug.log >/dev/null 2>&1 &)")
    time.sleep(10)
    before = audio.duration(desktop.wav)
    desktop.send_keys("meta_l")  # Activities overview
    time.sleep(2)
    type_text(desktop, "console")
    time.sleep(2)
    desktop.send_keys("ret")
    time.sleep(6)
    type_text(desktop, "echo hello")
    desktop.send_keys("ret")
    time.sleep(4)
    log = desktop.sh("grep -i 'SPEECH OUTPUT' /tmp/orca-debug.log | tail -n 200", check=False).lower()
    assert "console" in log, "Orca didn't announce the Console window"
    assert "hello" in log, "Orca didn't read the terminal output"
    spoken = audio.analyse(audio.tail(desktop.wav, before, desktop.wav + ".orca.wav"))
    assert spoken.voiced_seconds > 2
    assert spoken.longest_gap < 8, f"{spoken.longest_gap:.1f}s of silence after a user action"


def test_emacspeak_speaks(desktop):
    before = audio.duration(desktop.wav)
    desktop.sh("script -qc \"TERM=xterm emacs -nw -Q -l /opt/emacspeak/lisp/emacspeak-setup.el "
               "--eval '(progn (dtk-speak \\\"Blinux emacspeak test\\\") (sit-for 5) (kill-emacs))'\" "
               "/dev/null", timeout=120)
    spoken = audio.analyse(audio.tail(desktop.wav, before, desktop.wav + ".emacspeak.wav"))
    assert spoken.voiced_seconds > 0.5, "Emacspeak made no sound"


def test_screen_reader_setting(desktop):
    assert desktop.sh("gsettings get org.gnome.desktop.a11y.applications screen-reader-enabled") == "true"
    assert desktop.sh("gsettings get org.gnome.desktop.interface enable-animations") == "false"
