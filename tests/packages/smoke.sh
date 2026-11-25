#!/usr/bin/env bash
# Layer 3: install each Blinux package into a fresh chroot and check that it
# works (make packages-tests).
#
# Usage: sudo tests/packages/smoke.sh [PACKAGE...]   (default: all of them)
#
# Each package gets its own pacstrap'ed root (so missing dependencies show up)
# and a short check run inside it with arch-chroot. Heavy stacks (hep, ml) are
# only smoke-tested when named explicitly or with SMOKE_HEAVY=1 (nightly).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_DIR="$(realpath "${REPO_DIR:-$ROOT_DIR/repo/x86_64}")"
[[ $EUID -eq 0 ]] || { echo "needs root (pacstrap)" >&2; exit 1; }
command -v pacstrap >/dev/null || { echo "install arch-install-scripts" >&2; exit 1; }

work="$(mktemp -d)"
trap 'umount -R "$work"/root-* 2>/dev/null || true; rm -rf "$work"' EXIT
conf="$work/pacman.conf"
cp /etc/pacman.conf "$conf"
printf '\n[blinux]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO_DIR" >>"$conf"

# Checks run inside the chroot, so nothing in them should expand here.
# shellcheck disable=SC2016
declare -A CHECK=(
    [yay]='useradd -m smoke && runuser -u smoke -- yay --version'
    [blinux-tools]='blinux-install --help >/dev/null &&
        blinux-install --dry-run --config /usr/share/blinux/smoke.json | grep -q "Installation complete" &&
        blinux-drivers --status'
    [blinux-config]='test -f /etc/dconf/db/local && test -f /etc/dconf/db/gdm &&
        visudo -cf /etc/sudoers.d/10-blinux-wheel &&
        grep -q AudioOutputMethod /etc/speech-dispatcher/clients/00-blinux.conf'
    [emacspeak]='echo "load /opt/emacspeak/servers/native-espeak/tclespeak.so; exit" | tclsh &&
        espeak-ng --stdout "Blinux test" | wc -c | awk "{exit !(\$1 > 1000)}" &&
        emacs --batch -Q --eval "(progn (setq dtk-program \"espeak\")
            (load-file \"/opt/emacspeak/lisp/emacspeak-setup.el\")
            (unless (featurep (quote emacspeak)) (kill-emacs 1)))" &&
        (cd /opt/emacspeak/js/node && node -e "require(\"speech-rule-engine\"); require(\"mathjax\")")'
    [aster-math]='test -x /opt/emacspeak/aster-math/lisp/lexer/lispify &&
        printf "\$x^2\$" | /opt/emacspeak/aster-math/lisp/lexer/lispify | grep -q inline-math &&
        emacs --batch -Q -L /opt/emacspeak/aster-math/ui --eval "(locate-library \"aster\")"'
    [blinux-hep]='root -b -q -e "gROOT->GetVersion()" && python -c "import ROOT"'
    [blinux-ml]='python -c "import torch, sklearn, pandas; torch.zeros(1)"'
)
HEAVY=(blinux-hep blinux-ml)

if (($#)); then
    targets=("$@")
else
    # DECtalk is proprietary and never built by Blinux CI (blinux-aster-setup).
    targets=(yay blinux-tools blinux-config emacspeak aster-math)
    [[ "${SMOKE_HEAVY:-0}" == 1 ]] && targets+=("${HEAVY[@]}")
fi

failed=()
for pkg in "${targets[@]}"; do
    root="$work/root-$pkg"
    mkdir -p "$root"
    echo "==> $pkg"
    if ! pacstrap -C "$conf" -c "$root" base "$pkg" >"$work/$pkg.log" 2>&1; then
        echo "FAIL: $pkg does not install" >&2
        tail -5 "$work/$pkg.log" >&2
        failed+=("$pkg")
        continue
    fi
    if [[ "$pkg" == blinux-tools ]]; then
        cp "$ROOT_DIR/tests/fixtures/install/minimal.json" "$root/usr/share/blinux/smoke.json"
    fi
    if arch-chroot "$root" bash -euo pipefail -c "${CHECK[$pkg]}" >"$work/$pkg.check" 2>&1; then
        echo "ok: $pkg"
    else
        echo "FAIL: $pkg installed but its check failed" >&2
        tail -10 "$work/$pkg.check" >&2
        failed+=("$pkg")
    fi
    umount -R "$root" 2>/dev/null || true
    rm -rf "$root"
done

if ((${#failed[@]})); then
    echo "smoke tests failed: ${failed[*]}" >&2
    exit 1
fi
echo "smoke tests passed: ${targets[*]}"
