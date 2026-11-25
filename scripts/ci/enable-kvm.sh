#!/usr/bin/env bash
# CI helper: make /dev/kvm usable on a GitHub-hosted Ubuntu runner, and fail
# fast if it's missing. QEMU without KVM is far too slow for the speech tests.
set -euo pipefail
if [[ ! -e /dev/kvm ]]; then
    echo "error: /dev/kvm is missing on this runner; integration tests need KVM" >&2
    exit 1
fi
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
    sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
ls -l /dev/kvm
