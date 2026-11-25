#!/usr/bin/env bash
# Download or publish a [blinux] package repo stored as GitHub Release assets.
#
# Usage:
#   scripts/repo-release.sh fetch   TAG [DIR]   # download assets into DIR
#   scripts/repo-release.sh publish TAG [DIR]   # upload DIR's db + packages to TAG
#
# TAG is "repo" (stable [blinux]) or "repo-testing" ([blinux-testing]).
# DIR defaults to repo/x86_64. Needs the GitHub CLI (gh) with GH_TOKEN set.
#
# pacman reads the repo straight from the release:
#   Server = https://github.com/OrghoN/Blinux/releases/download/repo
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmd="${1:?usage: repo-release.sh fetch|publish TAG [DIR]}"
tag="${2:?missing release tag}"
dir="${3:-$ROOT/repo/x86_64}"

case "$tag" in
    repo | repo-testing) ;;
    *) echo "refusing unknown repo tag: $tag" >&2; exit 2 ;;
esac
command -v gh >/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 1; }
mkdir -p "$dir"

case "$cmd" in
    fetch)
        if gh release view "$tag" >/dev/null 2>&1; then
            gh release download "$tag" --dir "$dir" --clobber
        else
            echo "release $tag does not exist yet; starting from an empty repo"
        fi
        ;;
    publish)
        if ! gh release view "$tag" >/dev/null 2>&1; then
            title="Blinux package repo ($tag)"
            gh release create "$tag" --title "$title" --prerelease \
                --notes "Rolling pacman repository. Not an ISO release; see the versioned releases for ISOs."
        fi
        # pacman needs real files named blinux.db / blinux.files, not symlinks.
        for link in blinux.db blinux.files blinux.db.sig blinux.files.sig; do
            if [[ -L "$dir/$link" ]]; then
                cp --remove-destination "$(readlink -f "$dir/$link")" "$dir/$link"
            fi
        done
        shopt -s nullglob
        assets=("$dir"/blinux.{db,files}{,.tar.zst}{,.sig} "$dir"/*.pkg.tar.zst "$dir"/*.pkg.tar.zst.sig)
        gh release upload "$tag" "${assets[@]}" --clobber
        # Drop assets for package versions that are no longer in the database.
        mapfile -t keep < <(printf '%s\n' "${assets[@]}" | xargs -n1 basename)
        while read -r name; do
            if ! printf '%s\n' "${keep[@]}" | grep -qxF "$name"; then
                gh release delete-asset "$tag" "$name" --yes
            fi
        done < <(gh release view "$tag" --json assets --jq '.assets[].name')
        ;;
    *)
        echo "unknown command: $cmd" >&2
        exit 2
        ;;
esac
