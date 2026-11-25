#!/usr/bin/env bash
# Compare this machine's explicitly installed packages with Blinux's lists.
#
# Usage: scripts/harvest-packages.sh
#
# Prints:
#   - installed here but in no list (candidates to add, or to put in ignore.txt)
#   - in a list but not installed here (fine, just for information)
# packages/ignore.txt entries may use shell globs such as ttf-*-nerd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/packages"

listed() {
    for f in *.txt; do
        [[ "$f" == ignore.txt ]] && continue
        sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$f"
    done | while read -r name; do
        if [[ "$name" == @* ]]; then
            pacman -Sgq "${name#@}" 2>/dev/null || true
        else
            echo "$name"
        fi
    done | sort -u
}

mapfile -t ignore < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' ignore.txt)
ignored() {
    local pkg="$1" pattern
    for pattern in "${ignore[@]}"; do
        # shellcheck disable=SC2053 # glob match is intended
        [[ "$pkg" == $pattern ]] && return 0
    done
    return 1
}

mapfile -t in_lists < <(listed)
mapfile -t installed < <(pacman -Qqe | sort -u)

echo "## Installed here but in no list"
comm -23 <(printf '%s\n' "${installed[@]}") <(printf '%s\n' "${in_lists[@]}") |
    while read -r pkg; do ignored "$pkg" || echo "  $pkg"; done

echo
echo "## In a list but not explicitly installed here"
comm -13 <(printf '%s\n' "${installed[@]}") <(printf '%s\n' "${in_lists[@]}") | sed 's/^/  /'
