#!/usr/bin/env bash
# Layer 3: every installer choice must resolve (make packages-tests).
#
# For each graphics choice (open, nvidia, nvidia-cuda) and every subset of the
# optional stacks, ask pacman (dry run, -Sp) to resolve blinux-base plus what
# the installer would install. Catches conflicts and missing dependencies
# without downloading anything. CUDA packages only get this check, since CI
# has no GPU.
#
# Needs root (pacman -Sy into a scratch database) and a built repo in
# repo/x86_64 (scripts/build-repo.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_DIR="$(realpath "${REPO_DIR:-$ROOT_DIR/repo/x86_64}")"
# shellcheck source=tools/lib/common.sh
source "$ROOT_DIR/tools/lib/common.sh"
# shellcheck source=tools/lib/drivers.sh
source "$ROOT_DIR/tools/lib/drivers.sh"
# shellcheck source=tools/lib/packages.sh
source "$ROOT_DIR/tools/lib/packages.sh"

[[ $EUID -eq 0 ]] || die "needs root (pacman -Sy into a scratch database)"
[[ -f "$REPO_DIR/blinux.db.tar.zst" ]] || die "no repo in $REPO_DIR: run scripts/build-repo.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
conf="$work/pacman.conf"
{
    sed -n '/^\[options\]/,/^\[/p' /etc/pacman.conf | sed '$d'
    printf '\n[core]\nInclude = /etc/pacman.d/mirrorlist\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n'
    printf '\n[blinux]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO_DIR"
} >"$conf"
mkdir -p "$work/db"
pacman -Sy --config "$conf" --dbpath "$work/db" >/dev/null

checks=0 failed=0
for graphics in open nvidia nvidia-cuda; do
    for ((mask = 0; mask < 1 << ${#STACKS[@]}; mask++)); do
        stacks=()
        for ((i = 0; i < ${#STACKS[@]}; i++)); do
            ((mask & (1 << i))) && stacks+=("${STACKS[i]}")
        done
        mapfile -t pkgs < <(echo blinux-base; read_list "$(list_file drivers-open)"; network_packages "$graphics" "${stacks[@]}")
        checks=$((checks + 1))
        if ! pacman -Sp --print-format '%n' --config "$conf" --dbpath "$work/db" "${pkgs[@]}" >"$work/out" 2>&1; then
            failed=$((failed + 1))
            echo "FAIL: graphics=$graphics stacks=[${stacks[*]}]" >&2
            grep -E '^(error|warning|:: )' "$work/out" | head -5 >&2
        fi
    done
done

echo "resolution matrix: $((checks - failed))/$checks combinations resolve"
((failed == 0))
