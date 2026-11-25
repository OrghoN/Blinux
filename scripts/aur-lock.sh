#!/usr/bin/env bash
# Re-resolve every AUR package Blinux needs and pin it in packages/aur.lock.
#
# Inputs:  packages/aur.txt, plus the depends/makedepends of pkgbuilds/*
#          that the official repos can't satisfy.
# Output:  packages/aur.lock ("<pkgbase> <version> <commit>", build order).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mapfile -t names < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' packages/aur.txt)
mapfile -t local_pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' pkgbuilds/ORDER)

# Our own packages (and their split package names) are built locally.
local_names=()
for pkg in "${local_pkgs[@]}"; do
    local_names+=("$pkg")
    if [[ -f "pkgbuilds/$pkg/.SRCINFO" ]]; then
        while read -r name; do local_names+=("$name"); done < <(awk '/^pkgname = / {print $3}' "pkgbuilds/$pkg/.SRCINFO")
        while read -r dep; do names+=("$dep"); done < <(awk '/^\t(make|check)?depends = / {print $3}' "pkgbuilds/$pkg/.SRCINFO")
    fi
done

scripts/aur-resolve.py --lock packages/aur.lock --local "${local_names[@]}" -- "${names[@]}" >/dev/null
echo "pinned $(grep -vc '^#' packages/aur.lock) AUR package bases in packages/aur.lock"
