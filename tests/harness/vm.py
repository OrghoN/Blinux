"""Drive Blinux in QEMU: serial console through pexpect, keys and screenshots
through QMP, and the guest's sound card recorded to a WAV file."""

from __future__ import annotations

import glob
import json
import os
import shlex
import shutil
import socket
import subprocess
import time
from dataclasses import dataclass, field

import pexpect

OVMF_CANDIDATES = [
    # Arch (edk2-ovmf)
    ("/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2/x64/OVMF_VARS.4m.fd"),
    # Debian/Ubuntu (ovmf)
    ("/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_VARS_4M.fd"),
    ("/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/OVMF/OVMF_VARS.fd"),
]

PROMPT = "BLINUX-TEST# "


def find_ovmf() -> tuple[str, str]:
    for code, vars_ in OVMF_CANDIDATES:
        if os.path.exists(code) and os.path.exists(vars_):
            return code, vars_
    raise RuntimeError("OVMF not found: install edk2-ovmf (Arch) or ovmf (Ubuntu)")


def extract_from_iso(iso: str, paths: list[str], dest: str) -> list[str]:
    """Copy files out of the ISO with xorriso; returns the local paths."""
    os.makedirs(dest, exist_ok=True)
    out = []
    for p in paths:
        local = os.path.join(dest, os.path.basename(p))
        subprocess.run(
            ["xorriso", "-osirrox", "on", "-indev", iso, "-extract", p, local],
            check=True,
            capture_output=True,
        )
        os.chmod(local, 0o644)
        out.append(local)
    return out


def live_kernel_cmdline(iso: str, work: str) -> str:
    """The speech boot entry's options, plus a serial console for the harness."""
    (entry,) = extract_from_iso(iso, ["/loader/entries/02-archiso-speech-linux.conf"], work)
    with open(entry) as fh:
        for line in fh:
            if line.startswith("options"):
                return line.split(None, 1)[1].strip() + " console=tty0 console=ttyS0,115200"
    raise RuntimeError("no options line in the speech boot entry")


@dataclass
class VM:
    name: str
    artifacts: str
    firmware: str = "uefi"  # or "bios"
    memory: str = "4G"
    cpus: int = 4
    network: bool = True
    disk: str | None = None
    iso: str | None = None
    kernel: tuple[str, str, str] | None = None  # (vmlinuz, initramfs, cmdline)
    extra: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        os.makedirs(self.artifacts, exist_ok=True)
        self.wav = os.path.join(self.artifacts, f"{self.name}.wav")
        self.serial_log = os.path.join(self.artifacts, f"{self.name}-serial.log")
        self.qmp_path = os.path.join(self.artifacts, f"{self.name}.qmp")
        self.proc: pexpect.spawn | None = None
        self._qmp: socket.socket | None = None
        self.started = 0.0

    # ------------------------------------------------------------ lifecycle

    def command(self) -> list[str]:
        cmd = [
            "qemu-system-x86_64",
            "-enable-kvm", "-cpu", "host", "-machine", "q35",
            "-m", self.memory, "-smp", str(self.cpus),
            "-display", "none", "-vga", "virtio",
            "-serial", "stdio", "-monitor", "none",
            "-qmp", f"unix:{self.qmp_path},server=on,wait=off",
            "-audiodev", f"wav,id=snd0,path={self.wav},out.frequency=16000,"
                         "out.channels=1,out.format=s16",
            "-device", "intel-hda", "-device", "hda-duplex,audiodev=snd0",
            "-device", "virtio-rng-pci",
        ]
        if self.network:
            cmd += ["-nic", "user,model=virtio-net-pci"]
        else:
            cmd += ["-nic", "none"]
        if self.firmware == "uefi":
            code, vars_template = find_ovmf()
            vars_copy = os.path.join(self.artifacts, f"{self.name}-OVMF_VARS.fd")
            if not os.path.exists(vars_copy):
                shutil.copy(vars_template, vars_copy)
            cmd += [
                "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
                "-drive", f"if=pflash,format=raw,file={vars_copy}",
            ]
        if self.disk:
            cmd += ["-drive", f"file={self.disk},if=virtio,format=qcow2"]
        if self.iso:
            cmd += ["-drive", f"file={self.iso},media=cdrom,readonly=on"]
            cmd += ["-boot", "order=dc" if self.kernel is None else "order=c"]
        if self.kernel:
            vmlinuz, initrd, append = self.kernel
            cmd += ["-kernel", vmlinuz, "-initrd", initrd, "-append", append]
        return cmd + self.extra

    def start(self) -> "VM":
        cmd = self.command()
        with open(os.path.join(self.artifacts, f"{self.name}-qemu.cmd"), "w") as fh:
            fh.write(shlex.join(cmd) + "\n")
        log = open(self.serial_log, "wb")
        self.proc = pexpect.spawn(cmd[0], cmd[1:], timeout=60, logfile=log)
        self.started = time.monotonic()
        return self

    def stop(self) -> None:
        if self.proc and self.proc.isalive():
            try:
                self.qmp("quit")
            except OSError:
                pass
            self.proc.expect(pexpect.EOF, timeout=30)
        if self._qmp:
            self._qmp.close()

    def __enter__(self) -> "VM":
        return self.start()

    def __exit__(self, *exc) -> None:
        if exc[0] is not None:
            try:
                self.screenshot("failure")
            except Exception:
                pass
        self.stop()

    def elapsed(self) -> float:
        return time.monotonic() - self.started

    # ------------------------------------------------------------ QMP

    def qmp(self, command: str, **arguments) -> dict:
        if self._qmp is None:
            deadline = time.monotonic() + 30
            while True:
                try:
                    s = socket.socket(socket.AF_UNIX)
                    s.connect(self.qmp_path)
                    break
                except OSError:
                    if time.monotonic() > deadline:
                        raise
                    time.sleep(0.5)
            self._qmp = s
            self._qmp_file = s.makefile("rw")
            json.loads(self._qmp_file.readline())  # greeting
            self._qmp_send("qmp_capabilities")
        return self._qmp_send(command, **arguments)

    def _qmp_send(self, command: str, **arguments) -> dict:
        msg = {"execute": command}
        if arguments:
            msg["arguments"] = arguments
        self._qmp_file.write(json.dumps(msg) + "\n")
        self._qmp_file.flush()
        while True:
            reply = json.loads(self._qmp_file.readline())
            if "return" in reply or "error" in reply:
                return reply

    def send_keys(self, *keys: str) -> None:
        """send_keys("ctrl", "alt", "f3") presses them together."""
        self.qmp("send-key", keys=[{"type": "qcode", "data": k} for k in keys])

    def screenshot(self, label: str) -> str:
        path = os.path.join(self.artifacts, f"{self.name}-{label}.ppm")
        self.qmp("screendump", filename=path)
        return path

    # ------------------------------------------------------------ serial

    def expect(self, pattern: str, timeout: int = 60) -> str:
        self.proc.expect(pattern, timeout=timeout)
        return self.proc.before.decode(errors="replace")

    def login(self, user: str = "root", password: str = "", timeout: int = 600) -> None:
        """Log in on the serial console and set a prompt we can match."""
        self.expect("login:", timeout=timeout)
        self.proc.sendline(user)
        if password:
            self.expect("Password:")
            self.proc.sendline(password)
        time.sleep(2)
        self.proc.sendline(f"PS1='{PROMPT}'; PROMPT='{PROMPT}'; unset RPROMPT; stty -echo cols 250")
        self.expect(PROMPT)

    def sh(self, command: str, timeout: int = 120, check: bool = True) -> str:
        """Run a shell command on the serial console; return its output."""
        marker = f"__RC_{int(time.time() * 1000)}__"
        self.proc.sendline(f"{command}; echo {marker}$?")
        self.proc.expect(rf"{marker}(\d+)", timeout=timeout)
        out = self.proc.before.decode(errors="replace")
        rc = int(self.proc.match.group(1))
        self.expect(PROMPT, timeout=30)
        out = out.split("\n", 1)[-1] if "\n" in out else out
        if check and rc != 0:
            raise AssertionError(f"`{command}` exited {rc}:\n{out}")
        return out.strip()

    def write_file(self, path: str, content: str) -> None:
        self.sh(f"mkdir -p {shlex.quote(os.path.dirname(path))}")
        self.sh(f"cat > {shlex.quote(path)} <<'BLINUX_EOF'\n{content}\nBLINUX_EOF")


def make_disk(path: str, size: str = "40G") -> str:
    subprocess.run(["qemu-img", "create", "-f", "qcow2", path, size], check=True, capture_output=True)
    return path


def newest_iso(out_dir: str = "out") -> str | None:
    isos = sorted(glob.glob(os.path.join(out_dir, "blinux-*.iso")), key=os.path.getmtime)
    return isos[-1] if isos else None
