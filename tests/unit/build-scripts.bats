#!/usr/bin/env bats
# The build helpers that don't need root.

load helpers

@test "aur-resolve strips version constraints" {
    run python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('r', '$REPO/scripts/aur-resolve.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.strip_version('tcl=8.6.16-1') == 'tcl'
assert m.strip_version('python>=3') == 'python'
assert m.strip_version('clhep>=2.4.6.0') == 'clhep'
assert m.strip_version('zsh') == 'zsh'
print('ok')"
    [ "$output" = ok ]
}

@test "aur.lock lines are '<pkgbase> <version> <40-char commit>'" {
    run awk '!/^#/ && !($3 ~ /^[0-9a-f]{40}$/ && NF == 3) {print "bad: " $0; bad=1} END {exit bad}' \
        "$REPO/packages/aur.lock"
    [ "$status" -eq 0 ]
}

@test "blinux-meta matches packages/*.txt" {
    command -v pacman >/dev/null || skip "needs pacman to expand groups"
    run "$REPO/scripts/gen-meta.sh" --check
    [ "$status" -eq 0 ]
}

@test "every local PKGBUILD has an up-to-date .SRCINFO" {
    command -v makepkg >/dev/null || skip "needs makepkg"
    local d
    for d in "$REPO"/pkgbuilds/*/; do
        (cd "$d" && makepkg --printsrcinfo 2>/dev/null | diff -q - .SRCINFO >/dev/null) ||
            { echo "stale .SRCINFO in $d"; return 1; }
    done
}

@test "pkgbuilds/ORDER lists every local package exactly once" {
    run bash -c "cd '$REPO/pkgbuilds' && diff <(ls -d */ | tr -d / | sort) <(grep -v '^#' ORDER | sort)"
    [ "$status" -eq 0 ]
}
