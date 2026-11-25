#!/usr/bin/env bash
# Layer 1: the README's commands must match the repository (make lint-docs).
#
# For every fenced sh/bash/console block in README.md:
#   - the block parses as bash (bash -n)
#   - every ./scripts/... or scripts/... path it names exists
#   - every blinux-* command it names exists in tools/bin
#   - every "make TARGET" names a real Makefile target
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
README="${1:-README.md}"
fail=0
err() { echo "FAIL: $README: $*" >&2; fail=1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Split fenced shell blocks into files.
awk -v dir="$tmp" '
    /^```(sh|bash|shell|console)[[:space:]]*$/ {n++; inblock=1; next}
    /^```/ && inblock {inblock=0; next}
    inblock {print > (dir "/block" n ".sh")}
' "$README"

shopt -s nullglob
blocks=("$tmp"/block*.sh)
targets="$(sed -n 's/^\([a-zA-Z][a-zA-Z0-9_-]*\):.*/\1/p' Makefile)"

for b in "${blocks[@]}"; do
    # Allow "$ " prompts in console blocks.
    sed -i 's/^\$ //' "$b"
    bash -n "$b" 2>"$tmp/err" || err "a shell block does not parse: $(cat "$tmp/err")"
    while read -r path; do
        [[ -e "${path#./}" ]] || err "names $path, which does not exist"
    done < <(grep -oE '(\./)?scripts/[A-Za-z0-9_./-]+' "$b" | sort -u)
    while read -r cmd; do
        [[ -x "tools/bin/$cmd" ]] || err "names the command $cmd, which is not in tools/bin"
    done < <(grep -oE '(^|[[:space:]])blinux-[a-z-]+' "$b" | sed 's/^[[:space:]]*//' | sort -u |
        grep -v '^blinux-\(base\|aster\|docs\|hep\|ml\|ml-cuda\|config\|tools\|keyring\|testing\)$' || true)
    # "make TARGET" must be one of ours, until the block cd's into another
    # project (e.g. the Emacspeak build steps, which use Emacspeak's Makefile).
    while read -r target; do
        grep -qxF "$target" <<<"$targets" || err "runs make $target, which is not a Makefile target"
    done < <(awk '/^[[:space:]]*cd / && $2 != "Blinux" {exit} {print}' "$b" |
        grep -oE '(^|[[:space:]])make [a-z][a-z0-9-]*' | awk '{print $2}' | sort -u)
done

if ((fail)); then exit 1; fi
echo "README commands OK (${#blocks[@]} shell blocks)"
