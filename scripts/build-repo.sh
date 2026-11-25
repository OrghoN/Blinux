#!/usr/bin/env bash
# Build the [blinux] package repository.
#
# Builds, in order:
#   1. AUR packages pinned in packages/aur.lock (dependencies first)
#   2. Blinux's own packages, in the order listed in pkgbuilds/ORDER
# and adds them to repo/x86_64/blinux.db.
#
# Usage:
#   sudo scripts/build-repo.sh [--mode chroot|nodeps] [--only PKG...] [--force]
#
# Modes:
#   chroot  (default) clean-chroot builds with devtools. Needs root and devtools.
#           This is what CI and releases use.
#   nodeps  makepkg -d on the host, skipping dependency checks. Only useful for
#           data-only packages (blinux-config, blinux-tools, blinux-meta) when
#           testing packaging without root.
#
# Environment:
#   REPO_DIR     output directory (default: repo/x86_64)
#   BUILD_DIR    scratch directory (default: build)
#   GPGKEY       if set, sign every package and the database with this key
#   BUILD_USER   unprivileged user for builds when running as root (default: builder,
#                or $SUDO_USER when run through sudo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/repo/x86_64}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
CHROOT_DIR="$BUILD_DIR/chroot"
REPO_NAME=blinux
MODE=chroot
FORCE=0
ONLY=()

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

while (($#)); do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --only) shift; while (($#)) && [[ "$1" != --* ]]; do ONLY+=("$1"); shift; done ;;
        --force) FORCE=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

wanted() {
    # True if PKG should be built given --only.
    local pkg="$1"
    ((${#ONLY[@]} == 0)) && return 0
    local o
    for o in "${ONLY[@]}"; do [[ "$o" == "$pkg" ]] && return 0; done
    return 1
}

build_user() {
    if [[ -n "${BUILD_USER:-}" ]]; then
        echo "$BUILD_USER"
    elif [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    else
        echo builder
    fi
}

as_user() {
    # makepkg refuses to run as root, even for --packagelist.
    if [[ $EUID -eq 0 ]]; then
        runuser -u "$(build_user)" -- "$@"
    else
        "$@"
    fi
}

ensure_repo() {
    mkdir -p "$REPO_DIR"
    if [[ ! -f "$REPO_DIR/$REPO_NAME.db.tar.zst" ]]; then
        log "Creating empty $REPO_NAME database"
        repo-add -q "$REPO_DIR/$REPO_NAME.db.tar.zst"
    fi
}

ensure_chroot() {
    [[ $EUID -eq 0 ]] || die "chroot mode needs root (run with sudo)"
    command -v mkarchroot >/dev/null || die "install devtools: pacman -S devtools"
    local conf="$BUILD_DIR/chroot-pacman.conf"
    local base_conf=/usr/share/devtools/pacman.conf.d/extra.conf
    [[ -f "$base_conf" ]] || base_conf=/etc/pacman.conf
    mkdir -p "$CHROOT_DIR"
    {
        cat "$base_conf"
        printf '\n[%s]\nSigLevel = Optional TrustAll\nServer = file:///srv/blinux-repo\n' "$REPO_NAME"
    } >"$conf"
    if [[ ! -d "$CHROOT_DIR/root" ]]; then
        log "Creating clean chroot in $CHROOT_DIR/root"
        mkdir -p "$CHROOT_DIR/root/srv/blinux-repo"
        cp -a "$REPO_DIR/." "$CHROOT_DIR/root/srv/blinux-repo/"
        mkarchroot -C "$conf" "$CHROOT_DIR/root" base-devel
    fi
    sync_chroot_repo
}

sync_chroot_repo() {
    [[ "$MODE" == chroot ]] || return 0
    mkdir -p "$CHROOT_DIR/root/srv/blinux-repo"
    rsync -a --delete "$REPO_DIR/" "$CHROOT_DIR/root/srv/blinux-repo/"
    arch-nspawn "$CHROOT_DIR/root" pacman -Syu --noconfirm >/dev/null
}

stage_local() {
    # Copy pkgbuilds/PKG to the build dir, adding repo trees some packages need.
    local pkg="$1" dest="$BUILD_DIR/pkgs/$1"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$ROOT/pkgbuilds/$pkg/." "$dest/"
    case "$pkg" in
        blinux-tools)
            mkdir -p "$dest/files"
            cp -a "$ROOT/tools" "$ROOT/packages" "$dest/files/"
            ;;
        blinux-config)
            cp -a "$ROOT/config" "$dest/files"
            ;;
    esac
    echo "$dest"
}

stage_aur() {
    # Clone an AUR package base at its pinned commit.
    local base="$1" commit="$2" dest="$BUILD_DIR/aur/$1"
    if [[ ! -d "$dest/.git" ]]; then
        rm -rf "$dest"
        git clone -q "https://aur.archlinux.org/$base.git" "$dest"
    fi
    git -C "$dest" fetch -q origin
    git -C "$dest" checkout -q --detach "$commit"
    echo "$dest"
}

package_list() {
    # Packages makepkg would produce, minus -debug packages (debug builds are
    # optional and never produced for arch=any).
    (cd "$1" && as_user makepkg --packagelist 2>/dev/null) | grep -v -- '-debug-' || true
}

already_built() {
    local dir="$1" f
    ((FORCE)) && return 1
    while read -r f; do
        [[ -f "$REPO_DIR/$(basename "$f")" ]] || return 1
    done < <(package_list "$dir")
    return 0
}

build_dir() {
    local dir="$1" user
    user="$(build_user)"
    if already_built "$dir"; then
        log "$(basename "$dir") is up to date"
        return 0
    fi
    log "Building $(basename "$dir")"
    [[ $EUID -eq 0 ]] && chown -R "$user" "$dir"
    case "$MODE" in
        chroot)
            (cd "$dir" && makechrootpkg -c -U "$user" -r "$CHROOT_DIR" -- --noconfirm)
            ;;
        nodeps)
            (cd "$dir" && as_user makepkg -d -f --noconfirm)
            ;;
        *) die "unknown mode $MODE" ;;
    esac
    add_to_repo "$dir"
}

add_to_repo() {
    local dir="$1" f pkgs=()
    while read -r f; do
        [[ -f "$f" ]] || die "expected package not built: $f"
        cp -f "$f" "$REPO_DIR/"
        pkgs+=("$REPO_DIR/$(basename "$f")")
    done < <(package_list "$dir")
    if [[ -n "${GPGKEY:-}" ]]; then
        for f in "${pkgs[@]}"; do
            gpg --batch --yes --detach-sign --use-agent -u "$GPGKEY" "$f"
        done
        repo-add -q -s -v -k "$GPGKEY" -R "$REPO_DIR/$REPO_NAME.db.tar.zst" "${pkgs[@]}"
    else
        repo-add -q -R "$REPO_DIR/$REPO_NAME.db.tar.zst" "${pkgs[@]}"
    fi
    sync_chroot_repo
}

main() {
    ensure_repo
    [[ "$MODE" == chroot ]] && ensure_chroot

    if [[ "$MODE" == chroot ]]; then
        local base _version commit
        while read -r base _version commit; do
            [[ -z "$base" || "$base" == \#* ]] && continue
            wanted "$base" || continue
            build_dir "$(stage_aur "$base" "$commit")"
        done <"$ROOT/packages/aur.lock"
    else
        log "nodeps mode: skipping AUR packages"
    fi

    local pkg
    while read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        wanted "$pkg" || continue
        if [[ "$MODE" == nodeps ]] && [[ "$pkg" != blinux-* ]]; then
            log "nodeps mode: skipping $pkg (has real build dependencies)"
            continue
        fi
        build_dir "$(stage_local "$pkg")"
    done <"$ROOT/pkgbuilds/ORDER"

    log "Repository ready in $REPO_DIR"
}

main
