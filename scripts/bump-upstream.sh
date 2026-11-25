#!/usr/bin/env bash
# Check upstream projects for new versions and update the PKGBUILDs.
# upstream.yml runs this weekly and opens a pull request with the result, so
# every bump goes through CI and review like any other change.
#
# Usage: scripts/bump-upstream.sh
#
#   emacspeak   newest GitHub release of tvraman/emacspeak (via nvchecker)
#   aster-math  newest commit of tvraman/aster-math (pkgver = commit date)
#   dectalk     newest commit of dectalk/dectalk (pkgver = commit date)
#   AUR         re-pin every AUR package to its current commit (make lock)
#   meta        regenerate blinux-meta in case package groups changed (make meta)
#
# Needs: nvchecker, pacman-contrib (updpkgsums), git, curl, jq.
# Prints a summary of what changed (used as the pull request body).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
changes=()

set_var() { sed -i "s|^$2=.*|$2=$3|" "pkgbuilds/$1/PKGBUILD"; }
get_var() { sed -n "s|^$2=||p" "pkgbuilds/$1/PKGBUILD"; }
refresh() {
    (cd "pkgbuilds/$1" && updpkgsums >/dev/null 2>&1 && makepkg --printsrcinfo >.SRCINFO)
}

# --- emacspeak: GitHub releases
keyfile=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '[keys]\ngithub = "%s"\n' "$GITHUB_TOKEN" >"${TMPDIR:-/tmp}/nvchecker-keys.toml"
    keyfile=(-k "${TMPDIR:-/tmp}/nvchecker-keys.toml")
fi
latest="$(nvchecker -c .github/nvchecker.toml "${keyfile[@]}" --logger json 2>/dev/null |
    jq -r 'select(.name == "emacspeak") | .version' | tail -1)"
current="$(get_var emacspeak pkgver)"
if [[ -n "$latest" && "$latest" != "$current" ]]; then
    set_var emacspeak pkgver "$latest"
    set_var emacspeak pkgrel 1
    refresh emacspeak
    changes+=("emacspeak $current -> $latest")
fi

# --- git-pinned packages: newest commit, pkgver = commit date (YYYYMMDD)
bump_commit() {
    local pkg="$1" repo="$2" sha date old
    sha="$(git ls-remote "https://github.com/$repo.git" HEAD | cut -f1)"
    old="$(get_var "$pkg" _commit)"
    [[ -n "$sha" && "$sha" != "$old" ]] || return 0
    date="$(curl -fsS ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/commits/$sha" | jq -r '.commit.committer.date[0:10]' | tr -d -)"
    set_var "$pkg" _commit "$sha"
    set_var "$pkg" pkgver "$date"
    set_var "$pkg" pkgrel 1
    refresh "$pkg"
    changes+=("$pkg ${old:0:12} -> ${sha:0:12} ($date)")
}
bump_commit aster-math tvraman/aster-math
bump_commit dectalk dectalk/dectalk

# --- AUR pins and meta-packages
before="$(md5sum packages/aur.lock pkgbuilds/blinux-meta/PKGBUILD)"
scripts/aur-lock.sh >/dev/null
scripts/gen-meta.sh >/dev/null
if [[ "$before" != "$(md5sum packages/aur.lock pkgbuilds/blinux-meta/PKGBUILD)" ]]; then
    while read -r line; do changes+=("$line"); done < <(
        git diff --unified=0 packages/aur.lock | awk '/^[-+][a-z]/ {print}' |
            awk '{sign=substr($1,1,1); name=substr($1,2); v[name]=v[name] sign $2 " "}
                 END {for (n in v) print "AUR " n ": " v[n]}'
    )
    git diff --quiet pkgbuilds/blinux-meta || changes+=("blinux-meta regenerated (package groups changed)")
fi

if ((${#changes[@]} == 0)); then
    echo "Everything is up to date."
else
    echo "Upstream updates:"
    printf -- '- %s\n' "${changes[@]}"
fi
