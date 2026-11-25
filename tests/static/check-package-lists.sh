#!/usr/bin/env bash
# Layer 1: package list rules (make lint-lists).
#
#   - every name in packages/*.txt exists in the official repos, the AUR lock,
#     or Blinux's own pkgbuilds (skip with OFFLINE=1 when there's no sync db)
#   - no package appears in two stack lists
#   - deny-list: pipewire-pulse, wireplumber and xorg-server never appear
#     (audio and Wayland decisions); nvidia*, cuda* and cudnn never appear in
#     base.txt, iso.txt or the live ISO list (proprietary only at install time)
#   - the base stack always has the speech and audio essentials
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

names() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$@"; }
LISTS=(packages/base.txt packages/aster.txt packages/docs.txt packages/hep.txt packages/ml.txt
    packages/ml-cuda.txt packages/microcode.txt packages/drivers-open.txt
    packages/drivers-nvidia.txt packages/cuda.txt packages/iso.txt packages/aur.txt)

# --- deny-list everywhere
for f in "${LISTS[@]}" profile/packages.x86_64; do
    while read -r pkg; do
        case "$pkg" in
            pipewire-pulse | wireplumber) err "$f: $pkg conflicts with PulseAudio as the sound server" ;;
            xorg-server) err "$f: $pkg: Blinux ships no Xorg session (XWayland only)" ;;
        esac
    done < <(names "$f")
done

# --- no proprietary drivers in base or on the ISO
for f in packages/base.txt packages/iso.txt packages/drivers-open.txt profile/packages.x86_64; do
    while read -r pkg; do
        case "$pkg" in
            nvidia* | cuda* | cudnn | python-pytorch-cuda)
                err "$f: $pkg is proprietary; it may only be installed as an install-time choice" ;;
            broadcom-wl)
                # The stock Arch ISO (releng) ships broadcom-wl so Broadcom Wi-Fi
                # works on the live medium; it stays out of the installed base.
                [[ "$f" == profile/packages.x86_64 ]] ||
                    err "$f: broadcom-wl is non-free; only the installer may add it" ;;
        esac
    done < <(names "$f")
done

# --- base essentials
for pkg in sof-firmware espeakup espeak-ng orca speech-dispatcher pulseaudio pipewire \
    pipewire-media-session xorg-xwayland gdm yay base-devel git zsh emacs emacspeak \
    blinux-config blinux-tools; do
    names packages/base.txt | grep -qxF "$pkg" || err "packages/base.txt must include $pkg"
done

# --- no duplicates across stack lists
dups="$(for f in packages/base.txt packages/aster.txt packages/docs.txt packages/hep.txt packages/ml.txt; do
    names "$f" | sed "s|$| $f|"
done | sort | awk '{c[$1]++; w[$1] = w[$1] " " $2} END {for (p in c) if (c[p] > 1) print p ":" w[p]}')"
[[ -z "$dups" ]] || err "packages in more than one stack list: $dups"

# --- every package exists somewhere
if [[ "${OFFLINE:-0}" != 1 ]]; then
    mapfile -t local_pkgs < <(awk '/^pkgname = / {print $3}' pkgbuilds/*/.SRCINFO)
    mapfile -t aur_pkgs < <(awk '!/^#/ {print $1}' packages/aur.lock)
    known() {
        local p="$1"
        printf '%s\n' "${local_pkgs[@]}" "${aur_pkgs[@]}" | grep -qxF "$p" && return 0
        pacman -Si "$p" >/dev/null 2>&1 && return 0
        pacman -Sg "$p" >/dev/null 2>&1 && return 0
        # AUR packages may be listed by package name inside a split pkgbase.
        grep -q "pkgname = $p\$" build/aur/*/.SRCINFO 2>/dev/null && return 0
        return 1
    }
    for f in "${LISTS[@]}"; do
        while read -r pkg; do
            [[ "$pkg" == @* ]] && pkg="${pkg#@}"
            known "$pkg" || err "$f: $pkg is not in the official repos, packages/aur.lock or pkgbuilds/ (run make lock?)"
        done < <(names "$f")
    done
fi

if ((fail)); then exit 1; fi
echo "package lists OK"
