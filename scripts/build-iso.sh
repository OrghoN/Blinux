#!/usr/bin/env bash
# Build the Blinux ISO.
#
# Usage:
#   sudo scripts/build-iso.sh [--no-offline-cache]
#
# Needs: root, archiso, a built [blinux] repo (scripts/build-repo.sh).
#
# Steps:
#   1. Copy profile/ to build/iso-profile and point its pacman.conf at the local
#      [blinux] repo.
#   2. Download blinux-base and its whole dependency closure (plus microcode and
#      the open-source graphics drivers) into airootfs/opt/blinux/offline-repo,
#      so a base install works with no network.
#   3. Run mkarchiso and write checksums next to the ISO in out/.
#
# Environment:
#   REPO_DIR   [blinux] repo to use (default: repo/x86_64)
#   BUILD_DIR  scratch directory (default: build)
#   OUT_DIR    where the ISO goes (default: out)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(realpath -m "${REPO_DIR:-$ROOT/repo/x86_64}")"
BUILD_DIR="$(realpath -m "${BUILD_DIR:-$ROOT/build}")"
OUT_DIR="$(realpath -m "${OUT_DIR:-$ROOT/out}")"
PROFILE="$BUILD_DIR/iso-profile"
OFFLINE=1

while (($#)); do
    case "$1" in
        --no-offline-cache) OFFLINE=0; shift ;;
        -h | --help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "mkarchiso needs root: run with sudo"
command -v mkarchiso >/dev/null || die "install archiso: pacman -S archiso"
[[ -f "$REPO_DIR/blinux.db.tar.zst" ]] || die "no [blinux] repo in $REPO_DIR; run scripts/build-repo.sh first"

# Reproducible timestamps: use the last commit's time.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}"
export SOURCE_DATE_EPOCH

log "Preparing profile in $PROFILE"
rm -rf "$PROFILE"
mkdir -p "$PROFILE"
cp -a "$ROOT/profile/." "$PROFILE/"
printf '\n[blinux]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO_DIR" >>"$PROFILE/pacman.conf"

read_list() {
    # Print package names from a list file, skipping comments and blank lines.
    sed -e 's/#.*//' -e 's/[[:space:]]\+$//' -e '/^$/d' "$@"
}

# Live ISO packages: the releng set plus packages/iso.txt.
read_list "$ROOT/packages/iso.txt" >>"$PROFILE/packages.x86_64"

if ((OFFLINE)); then
    offline="$PROFILE/airootfs/opt/blinux/offline-repo"
    dbpath="$BUILD_DIR/offline-db"
    log "Downloading the base stack into the offline cache"
    rm -rf "$offline" "$dbpath"
    mkdir -p "$offline" "$dbpath"
    mapfile -t base_pkgs < <(
        echo blinux-base
        read_list "$ROOT/packages/microcode.txt" "$ROOT/packages/drivers-open.txt"
    )
    pacman -Syw --noconfirm --config "$PROFILE/pacman.conf" --dbpath "$dbpath" \
        --cachedir "$offline" "${base_pkgs[@]}"
    repo-add -q "$offline/blinux-offline.db.tar.zst" "$offline"/*.pkg.tar.zst
    log "Offline cache: $(du -sh "$offline" | cut -f1)"
fi

log "Running mkarchiso"
mkdir -p "$OUT_DIR"
rm -rf "$BUILD_DIR/iso-work"
mkarchiso -v -w "$BUILD_DIR/iso-work" -o "$OUT_DIR" "$PROFILE"

log "Writing checksums"
(
    cd "$OUT_DIR"
    sha256sum blinux-*.iso >sha256sums
    b2sum blinux-*.iso >b2sums
)
iso="$(find "$OUT_DIR" -maxdepth 1 -name 'blinux-*.iso' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)"
size=$(stat -c %s "$iso")
log "Built $iso ($((size / 1024 / 1024)) MiB)"
if ((size > 2 * 1024 * 1024 * 1024)); then
    echo "warning: ISO is over 2 GiB, which is GitHub's release asset limit" >&2
fi
