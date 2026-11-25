#!/usr/bin/env bash
# Layer 1: configuration validity (make lint-configs).
#
#   - dconf keyfiles compile; sudoers parses; JSON parses
#   - Emacs Lisp startup files byte-compile; zsh files parse
#   - systemd drop-ins and pacman hooks are well-formed INI
#   - install config fixtures match the JSON schema (needs python jsonschema)
#   - the live ISO boots the speech entry by default in every boot loader
#   - nothing turns Wayland off
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

need() { command -v "$1" >/dev/null || { echo "skip: $1 not installed" >&2; return 1; }; }

# --- dconf
if need dconf; then
    for db in config/etc/dconf/db/*.d; do
        dconf compile "$tmp/$(basename "$db")" "$db" || err "dconf keyfile in $db does not compile"
    done
fi

# --- sudoers
if need visudo; then
    for f in config/etc/sudoers.d/*; do
        visudo -cqf "$f" || err "$f: sudoers syntax error"
    done
fi

# --- JSON
while read -r f; do
    jq empty "$f" 2>/dev/null || err "$f: invalid JSON"
done < <(git ls-files '*.json')

# --- Emacs Lisp
if need emacs; then
    while read -r f; do
        cp "$f" "$tmp/"
        emacs --batch -Q -f batch-byte-compile "$tmp/$(basename "$f")" 2>"$tmp/elc.log" ||
            { err "$f does not byte-compile"; cat "$tmp/elc.log" >&2; }
    done < <(git ls-files '*.el')
fi

# --- zsh
if need zsh; then
    for f in config/usr/share/blinux/zsh/zshrc config/etc/skel/.zshrc profile/airootfs/root/.zshrc; do
        zsh -n "$f" || err "$f: zsh syntax error"
    done
fi

# --- INI-style files: systemd drop-ins, pacman hooks
check_ini() {
    awk -v f="$1" '
        /^[[:space:]]*(#|;|$)/ {next}
        /^\[[A-Za-z]+\]$/ {sections++; next}
        /^[A-Za-z][A-Za-z0-9_]*[[:space:]]*=/ { if (!sections) {print f ": key before any section: " $0; bad=1}; next}
        /^[A-Za-z][A-Za-z0-9_]*$/ {next}
        {print f ": not a key, section or comment: " $0; bad=1}
        END {exit bad}' "$1" >&2 || err "$1 is malformed"
}
check_ini config/usr/share/blinux/console-speech/espeakup-pulse.conf
sed -n "/write_file \"\$NVIDIA_HOOK\" <<'EOF'/,/^EOF/p" tools/lib/drivers.sh | sed '1d;$d' >"$tmp/nvidia.hook"
check_ini "$tmp/nvidia.hook"

# --- install config fixtures against the schema
if python3 -c 'import jsonschema' 2>/dev/null; then
    python3 - tools/share/install-config.schema.json tests/fixtures/install/*.json <<'PY' || err "install config fixtures don't match the schema"
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
jsonschema.Draft202012Validator.check_schema(schema)
bad = 0
for path in sys.argv[2:]:
    try:
        jsonschema.validate(json.load(open(path)), schema)
    except jsonschema.ValidationError as e:
        print(f"{path}: {e.message}", file=sys.stderr)
        bad = 1
sys.exit(bad)
PY
else
    echo "skip: python jsonschema not installed" >&2
fi

# --- speech is the default boot entry everywhere
grep -qx 'default 02-archiso-speech-linux.conf' profile/efiboot/loader/loader.conf ||
    err "systemd-boot (UEFI) must default to the speech entry"
grep -q 'accessibility=on' profile/efiboot/loader/entries/02-archiso-speech-linux.conf ||
    err "the systemd-boot speech entry must pass accessibility=on"
grep -qx 'DEFAULT archspeech' profile/syslinux/archiso_sys.cfg ||
    err "syslinux (BIOS) must default to the speech entry"
for f in profile/grub/grub.cfg profile/grub/loopback.cfg; do
    grep -qx 'default=archlinux-accessibility' "$f" || err "$f must default to the speech entry"
done
for f in profile/efiboot/loader/loader.conf; do
    t="$(awk '/^timeout/ {print $2}' "$f")"
    ((t <= 10)) || err "$f: boot menu timeout should be short (is $t s)"
done

# --- Wayland stays on
if grep -rqs 'WaylandEnable=false' config tools profile; then
    err "something sets WaylandEnable=false; Blinux is Wayland-only"
fi

if ((fail)); then exit 1; fi
echo "configs OK"
