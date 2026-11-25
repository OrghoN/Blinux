"""Install a fixture case into a fresh disk image and boot the result."""

from __future__ import annotations

import json
import os

from .vm import VM, make_disk

TEST_PASSWORD = "blinux-test"


def install_case(name: str, case: dict, iso: str, live_kernel, artifacts: str,
                 dotfiles_url: str | None = None) -> str:
    """Run blinux-install --config for CASE on a new disk; return the disk path."""
    disk = make_disk(os.path.join(artifacts, f"{name}.qcow2"))
    online = name != "offline"
    case = dict(case)
    if dotfiles_url and case.get("dotfiles", {}).get("enabled"):
        case["dotfiles"]["url"] = dotfiles_url
    with VM(f"{name}-install", artifacts, firmware=case.get("firmware", "uefi"),
            network=online, disk=disk, iso=iso, kernel=live_kernel) as vm:
        vm.login("root", timeout=600)
        vm.write_file("/root/case.json", json.dumps(case, indent=2))
        out = vm.sh("blinux-install --config /root/case.json 2>&1 | tee /root/install.out",
                    timeout=3 * 3600)
        assert "Installation complete." in out, out[-2000:]
        prepare_first_boot(vm, case)
        vm.sh("systemctl poweroff", check=False, timeout=30)
    return disk


def prepare_first_boot(vm: VM, case: dict) -> None:
    """Test-only changes to the installed system: a serial console so the
    harness can log in, and nothing else."""
    root_part = "/dev/vda2" if case.get("firmware", "uefi") == "uefi" else "/dev/vda3"
    boot_part = "/dev/vda1" if case.get("firmware", "uefi") == "uefi" else "/dev/vda2"
    if case.get("encrypt"):
        vm.sh(f"printf %s {json.dumps(case['passphrase'])} | "
              f"cryptsetup open --key-file=- {root_part} blinuxroot")
        root_part = "/dev/mapper/blinuxroot"
    vm.sh(f"mount {root_part} /mnt && mount {boot_part} /mnt/boot")
    if case.get("firmware", "uefi") == "uefi":
        vm.sh("sed -i 's/^options .*/& console=tty0 console=ttyS0,115200/' "
              "/mnt/boot/loader/entries/blinux.conf")
    else:
        vm.sh("sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&console=tty0 console=ttyS0,115200 /' "
              "/mnt/etc/default/grub && arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg")
    vm.sh("umount -R /mnt")
    if case.get("encrypt"):
        vm.sh("cryptsetup close blinuxroot")


def boot_installed(name: str, case: dict, disk: str, artifacts: str, label: str = "boot",
                   network: bool = True) -> VM:
    vm = VM(f"{name}-{label}", artifacts, firmware=case.get("firmware", "uefi"),
            network=network, disk=disk)
    vm.start()
    if case.get("encrypt"):
        vm.expect("passphrase", timeout=300)
        vm.proc.sendline(case["passphrase"])
    return vm
