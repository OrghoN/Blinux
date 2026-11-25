"""Layer 4: unattended installs of every fixture case, then the first boot.

Each case in tests/fixtures/install/*.json is installed on a fresh disk with
`blinux-install --config`, then booted, and checked over the serial console.
"""

import time

import pytest

from conftest import load_case
from harness import audio
from harness.install import TEST_PASSWORD, boot_installed, install_case


@pytest.fixture
def installed(case, iso, live_kernel, artifacts, request):
    cfg = load_case(case)
    dotfiles = None
    if cfg.get("dotfiles", {}).get("enabled"):
        dotfiles = request.getfixturevalue("dotfiles_server")
    disk = install_case(case, cfg, iso, live_kernel, artifacts, dotfiles)
    vm = boot_installed(case, cfg, disk, artifacts, network=case != "offline")
    try:
        vm.login(cfg["username"], TEST_PASSWORD, timeout=900)
        yield case, cfg, vm
    finally:
        vm.stop()


def wait_for(vm, command, message, timeout=180):
    deadline = time.monotonic() + timeout
    while not vm.sh(f"{command} >/dev/null && echo yes || true"):
        assert time.monotonic() < deadline, message
        time.sleep(5)


def sudo(vm, command, **kw):
    return vm.sh(f"echo {TEST_PASSWORD} | sudo -S -p '' {command}", **kw)


def test_first_boot(installed):
    case, cfg, vm = installed

    # --- phase 1: the GDM greeter speaks
    assert vm.sh("systemctl is-active gdm.service") == "active"
    wait_for(vm, "pgrep -u gdm -x orca", "Orca never started at the GDM greeter")
    time.sleep(20)
    assert audio.analyse(vm.wav).voiced_seconds > 1, "the GDM greeter is silent"

    # --- phase 2: log the test user in (test-only autologin), so their
    # PulseAudio owns the sound card the way a real desktop login does
    vm.write_file("/tmp/custom.conf",
                  f"[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin={cfg['username']}")
    sudo(vm, "install -m644 /tmp/custom.conf /etc/gdm/custom.conf")
    sudo(vm, "systemctl restart gdm.service")
    wait_for(vm, "pgrep -u $(id -u) -x gnome-shell", "the GNOME session never started")
    wait_for(vm, "pgrep -u $(id -u) -x orca", "Orca didn't start in the session")
    session = vm.sh("loginctl list-sessions --no-legend | awk -v u=$(id -un) '$3 == u && $4 == \"seat0\" {print $1}'")
    assert vm.sh(f"loginctl show-session {session} -p Type --value") == "wayland"
    # XWayland starts on demand for an X11 client (Tk's wish, pulled in by tclx).
    vm.sh("(DISPLAY=:0 timeout 15 wish <<< 'after 8000 exit' >/dev/null 2>&1 &)")
    wait_for(vm, "pgrep -x Xwayland", "XWayland didn't start for an X11 client", timeout=30)

    # --- audio stack: PulseAudio is the server, PipeWire only for video
    assert sudo(vm, "pacman -Q pipewire-pulse 2>/dev/null || echo absent") == "absent"
    assert sudo(vm, "pacman -Q wireplumber 2>/dev/null || echo absent") == "absent"
    assert "Server Name: pulseaudio" in vm.sh("pactl info")
    assert vm.sh("pgrep -x pipewire >/dev/null && echo running") == "running"
    before = audio.duration(vm.wav)
    vm.sh("spd-say -w 'Blinux speech test'", timeout=60)
    spoken = audio.analyse(audio.tail(vm.wav, before, vm.wav + ".spd.wav"))
    assert spoken.voiced_seconds > 0.5, "speech-dispatcher produced no sound"

    # --- shell, AUR helper, defaults
    assert vm.sh("getent passwd $(id -un) | cut -d: -f7") == "/usr/bin/zsh"
    assert vm.sh("yay --version").startswith("yay v")
    assert vm.sh("test -f ~/.config/yay/config.json && echo yes") == "yes"
    assert vm.sh("test -f /usr/share/emacs/site-lisp/site-start.d/50-emacspeak.el && echo yes") == "yes"
    assert vm.sh("emacs --batch -Q --eval '(progn (setq dtk-program \"espeak\") "
                 "(load-file \"/opt/emacspeak/lisp/emacspeak-setup.el\") "
                 "(princ (featurep (quote emacspeak))))'") .endswith("t")
    assert sudo(vm, "passwd -S root").split()[1] == "L"

    # --- case-specific checks
    graphics = vm.sh("cat /etc/blinux/graphics")
    if case == "offline":
        assert graphics == "open", "offline installs must fall back to open source drivers"
        assert vm.sh("pacman -Q nvidia-open 2>/dev/null || echo absent") == "absent"
    elif case == "nvidia-cuda":
        assert graphics == "nvidia-cuda"
        assert "nvidia_drm.modeset=1" in vm.sh("cat /proc/cmdline")
        assert vm.sh("test -f /etc/mkinitcpio.conf.d/20-blinux-nvidia.conf && echo yes") == "yes"
        vm.sh("pacman -Q nvidia-open cuda cudnn python-pytorch-cuda blinux-ml-cuda")
    else:
        assert graphics == cfg.get("graphics", "open")

    if case == "all-stacks":
        vm.sh("pacman -Q blinux-aster blinux-docs blinux-hep blinux-ml")
        assert vm.sh("readlink ~/.zshrc").endswith("/.dotfiles/.zshrc")
        assert vm.sh("readlink ~/.emacs.d/init.el").endswith("/.dotfiles/init.el")

    if case == "encrypted" or case == "bios":
        assert "crypt" in vm.sh("lsblk -no TYPE /dev/vda* | sort -u | tr '\\n' ' '")

    if case == "console-speech":
        assert vm.sh("systemctl is-enabled espeakup.service") == "enabled"
        # TTY hand-off: speech on a text console, then back to the desktop.
        before = audio.duration(vm.wav)
        vm.send_keys("ctrl", "alt", "f3")
        time.sleep(10)
        assert audio.analyse(audio.tail(vm.wav, before, vm.wav + ".tty3.wav")).voiced_seconds > 0.5, \
            "espeakup is silent on tty3"
        vm.send_keys("ctrl", "alt", "f1")
        time.sleep(10)
        before = audio.duration(vm.wav)
        vm.sh("spd-say -w 'Back on the desktop'", timeout=60)
        assert audio.analyse(audio.tail(vm.wav, before, vm.wav + ".back.wav")).voiced_seconds > 0.5, \
            "speech-dispatcher went silent after the TTY switch"
    else:
        assert vm.sh("systemctl is-enabled espeakup.service || true") == "disabled"
