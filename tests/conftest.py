"""Shared fixtures for the QEMU tests (layers 4 and 5).

    make test-iso CASES="minimal encrypted" FIRMWARE=uefi
    make test-a11y
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import pytest

sys.path.insert(0, os.path.dirname(__file__))

from harness.vm import extract_from_iso, live_kernel_cmdline, newest_iso  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES_DIR = os.path.join(REPO, "tests", "fixtures", "install")
ALL_CASES = sorted(f[:-5] for f in os.listdir(CASES_DIR) if f.endswith(".json"))
ARTIFACTS = os.path.join(REPO, "tests", "integration", "artifacts")


def pytest_addoption(parser):
    parser.addoption("--iso", default="", help="ISO to test (default: newest out/blinux-*.iso)")
    parser.addoption("--cases", default="", help="install cases to run (default: all)")
    parser.addoption("--firmware", default="", help="uefi, bios or both (default: both)")


def _selected(config, option, all_values):
    value = config.getoption(option)
    return value.split() if value else all_values


def pytest_generate_tests(metafunc):
    if "case" in metafunc.fixturenames:
        metafunc.parametrize("case", _selected(metafunc.config, "--cases", ALL_CASES))
    if "firmware" in metafunc.fixturenames:
        metafunc.parametrize("firmware", _selected(metafunc.config, "--firmware", ["uefi", "bios"]))


def pytest_collection_modifyitems(config, items):
    for item in items:
        if any(m in item.nodeid for m in ("test_install", "test_first_boot")):
            item.add_marker(pytest.mark.slow)


@pytest.fixture(scope="session")
def iso(request) -> str:
    path = request.config.getoption("--iso") or newest_iso(os.path.join(REPO, "out"))
    if not path or not os.path.exists(path):
        pytest.skip("no ISO: build one with `make iso` or pass --iso")
    if not os.path.exists("/dev/kvm"):
        pytest.fail("/dev/kvm is missing; these tests need KVM")
    for tool in ("qemu-system-x86_64", "qemu-img", "xorriso"):
        if not shutil.which(tool):
            pytest.fail(f"{tool} is not installed")
    return os.path.abspath(path)


@pytest.fixture(scope="session")
def artifacts() -> str:
    os.makedirs(ARTIFACTS, exist_ok=True)
    return ARTIFACTS


@pytest.fixture(scope="session")
def live_kernel(iso, tmp_path_factory) -> tuple[str, str, str]:
    """The ISO's own kernel and initramfs, with a serial console added."""
    work = str(tmp_path_factory.mktemp("live-kernel"))
    vmlinuz, initrd = extract_from_iso(
        iso, ["/arch/boot/x86_64/vmlinuz-linux", "/arch/boot/x86_64/initramfs-linux.img"], work
    )
    return vmlinuz, initrd, live_kernel_cmdline(iso, work)


def load_case(name: str) -> dict:
    with open(os.path.join(CASES_DIR, f"{name}.json")) as fh:
        return json.load(fh)


@pytest.fixture(scope="session")
def dotfiles_server(tmp_path_factory):
    """Serve tests/fixtures/dotfiles as a git repo at http://10.0.2.2:8000/dotfiles.git
    (10.0.2.2 is the host as seen from QEMU's user-mode network)."""
    root = tmp_path_factory.mktemp("git-http")
    src = root / "src"
    shutil.copytree(os.path.join(REPO, "tests", "fixtures", "dotfiles"), src)
    git = ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid"]
    subprocess.run(["git", "init", "-q", str(src)], check=True)
    subprocess.run(git + ["-C", str(src), "add", "-A"], check=True)
    subprocess.run(git + ["-C", str(src), "commit", "-qm", "fixture"], check=True)
    bare = root / "dotfiles.git"
    subprocess.run(["git", "clone", "-q", "--bare", str(src), str(bare)], check=True)
    subprocess.run(["git", "-C", str(bare), "update-server-info"], check=True)
    handler = partial(SimpleHTTPRequestHandler, directory=str(root))
    server = ThreadingHTTPServer(("0.0.0.0", 8000), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield "http://10.0.2.2:8000/dotfiles.git"
    server.shutdown()
