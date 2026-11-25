# shellcheck shell=bash
# Shared helpers for the Blinux tools (blinux-install, blinux-drivers,
# blinux-console-speech, blinux-dotfiles).
#
# Everything a user sees is plain text, one idea per line, with no colours,
# spinners or progress bars, so speakup on the console and Orca in a terminal
# read it cleanly. Questions are asked one at a time and read from stdin, which
# also lets the unit tests answer them.
#
# Environment:
#   DRY_RUN=1   print commands instead of running them (used by unit tests)
#   ROOT        target root for file edits (default /)
#   LOG_FILE    command log (default /dev/null)

DRY_RUN="${DRY_RUN:-0}"
ROOT="${ROOT:-/}"
LOG_FILE="${LOG_FILE:-/dev/null}"

# Locate the lib and data directories whether running from the repo or installed.
_blinux_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_blinux_common_dir/../../packages/base.txt" ]]; then
    BLINUX_PACKAGES="${BLINUX_PACKAGES:-$_blinux_common_dir/../../packages}"
    BLINUX_SCHEMA="${BLINUX_SCHEMA:-$_blinux_common_dir/../share/install-config.schema.json}"
else
    BLINUX_PACKAGES="${BLINUX_PACKAGES:-/usr/share/blinux/packages}"
    BLINUX_SCHEMA="${BLINUX_SCHEMA:-/usr/share/blinux/install-config.schema.json}"
fi
BLINUX_LIB="${BLINUX_LIB:-$_blinux_common_dir}"

say() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# rootpath PATH: PATH inside $ROOT ("/etc/x" -> "/mnt/etc/x").
rootpath() {
    local root="${ROOT%/}"
    printf '%s%s\n' "$root" "$1"
}

# run CMD...: run a command, or print it in dry-run mode. Always logged.
run() {
    {
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    } >>"$LOG_FILE"
    if [[ "$DRY_RUN" == 1 ]]; then
        printf 'DRY-RUN:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

# write_file PATH [MODE]: write stdin to PATH (inside $ROOT). Honours DRY_RUN.
write_file() {
    local path mode="${2:-0644}"
    path="$(rootpath "$1")"
    if [[ "$DRY_RUN" == 1 ]]; then
        printf 'DRY-RUN: write %s\n' "$path"
        cat >/dev/null
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    cat >"$path"
    chmod "$mode" "$path"
}

# remove_file PATH: delete PATH (inside $ROOT) if present. Honours DRY_RUN.
remove_file() {
    local path
    path="$(rootpath "$1")"
    [[ -e "$path" || -L "$path" ]] || return 0
    if [[ "$DRY_RUN" == 1 ]]; then
        printf 'DRY-RUN: remove %s\n' "$path"
    else
        rm -f "$path"
    fi
}

# read_list FILE...: package names from list files, without comments or blanks.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$@"
}

# list_file NAME: path of packages/NAME.txt
list_file() {
    local f="$BLINUX_PACKAGES/$1.txt"
    [[ -f "$f" ]] || die "package list not found: $f"
    printf '%s\n' "$f"
}

# ---------------------------------------------------------------- questions

# ask QUESTION [DEFAULT]: print the answer. An empty answer gives DEFAULT.
ask() {
    local question="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        say "$question Press Enter for $default." >&2
    else
        say "$question" >&2
    fi
    IFS= read -r answer || die "no answer (end of input)"
    printf '%s\n' "${answer:-$default}"
}

# ask_yes_no QUESTION DEFAULT(yes|no): return 0 for yes.
ask_yes_no() {
    local question="$1" default="${2:-no}" answer
    while true; do
        answer="$(ask "$question Answer yes or no." "$default")"
        case "${answer,,}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
            *) say "Please answer yes or no." >&2 ;;
        esac
    done
}

# choose QUESTION DEFAULT_INDEX OPTION...: print the chosen option's index
# (1-based). Each option is read out on its own line with its number.
choose() {
    local question="$1" default="$2"
    shift 2
    local options=("$@") n="$#" i answer
    say "$question" >&2
    for ((i = 1; i <= n; i++)); do
        say "Option $i of $n: ${options[i - 1]}." >&2
    done
    while true; do
        answer="$(ask "Type a number from 1 to $n." "$default")"
        if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= n)); then
            say "You chose: ${options[answer - 1]}." >&2
            printf '%s\n' "$answer"
            return 0
        fi
        say "That is not one of the options." >&2
    done
}

# ask_secret QUESTION: read a secret twice without echo; print it.
ask_secret() {
    local question="$1" first second
    while true; do
        say "$question Typing is silent." >&2
        IFS= read -r -s first || die "no answer (end of input)"
        say "Type it again to confirm." >&2
        IFS= read -r -s second || die "no answer (end of input)"
        if [[ -z "$first" ]]; then
            say "It can't be empty." >&2
        elif [[ "$first" != "$second" ]]; then
            say "They didn't match. Let's try again." >&2
        else
            printf '%s\n' "$first"
            return 0
        fi
    done
}

# confirm_twice QUESTION WORD: the user must type WORD, twice. Return 0 if so.
confirm_twice() {
    local question="$1" word="$2" answer
    say "$question" >&2
    answer="$(ask "To confirm, type $word.")"
    [[ "$answer" == "$word" ]] || return 1
    answer="$(ask "Are you sure? Type $word again.")"
    [[ "$answer" == "$word" ]]
}
