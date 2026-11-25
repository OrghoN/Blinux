#!/usr/bin/env bash
# CI helper: run a command inside a privileged Arch Linux container with the
# repository mounted at /src. mkarchiso and devtools' clean chroots need
# --privileged, which a GitHub Actions `container:` job can't provide.
#
# Usage: scripts/ci/arch-run.sh "extra packages" command [args...]
set -euo pipefail

pkgs="$1"
shift
image="${ARCH_IMAGE:-archlinux:base-devel}"

env_args=()
for var in GPGKEY GNUPGHOME SOURCE_DATE_EPOCH STRICT BUILD_USER; do
    [[ -n "${!var:-}" ]] && env_args+=(-e "$var")
done
mounts=(-v "$PWD:/src")
[[ -n "${GNUPGHOME:-}" ]] && mounts+=(-v "$GNUPGHOME:$GNUPGHOME")
[[ -e /dev/kvm ]] && mounts+=(--device /dev/kvm)

# shellcheck disable=SC2016 # expanded inside the container
docker run --rm --privileged "${mounts[@]}" "${env_args[@]}" -w /src "$image" \
    bash -euo pipefail -c '
        pkgs="$1"; shift
        # shellcheck disable=SC2086
        pacman -Syu --noconfirm --needed git rsync $pkgs >/dev/null
        id builder >/dev/null 2>&1 || useradd -m builder
        echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
        git config --global --add safe.directory /src
        mkdir -p /src/build /src/repo /src/out
        chown -R builder /src/build
        "$@"
    ' bash "$pkgs" "$@"
