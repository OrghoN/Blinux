#!/usr/bin/env bash
# CI helper: import the package signing key from a secret and cache its
# passphrase in gpg-agent, so both `gpg --detach-sign` and `repo-add -s` can
# sign without prompting.
#
# Reads:  SIGNING_KEY (armored private key), SIGNING_PASSPHRASE (may be empty)
# Writes: GNUPGHOME and GPGKEY to $GITHUB_ENV when running in Actions,
#         otherwise prints them as shell assignments.
set -euo pipefail

: "${SIGNING_KEY:?SIGNING_KEY is empty: add the secret to the repository environment}"
GNUPGHOME="${GNUPGHOME:-$(mktemp -d)}"
export GNUPGHOME
chmod 700 "$GNUPGHOME"
printf 'allow-preset-passphrase\ndefault-cache-ttl 21600\nmax-cache-ttl 21600\n' >"$GNUPGHOME/gpg-agent.conf"
gpgconf --kill gpg-agent || true

printf '%s\n' "$SIGNING_KEY" | gpg --batch --import
GPGKEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"

if [[ -n "${SIGNING_PASSPHRASE:-}" ]]; then
    preset="$(gpgconf --list-dirs libexecdir)/gpg-preset-passphrase"
    gpg --list-secret-keys --with-keygrip --with-colons | awk -F: '/^grp:/ {print $10}' |
        while read -r grip; do
            printf '%s' "$SIGNING_PASSPHRASE" | "$preset" --preset "$grip"
        done
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'GNUPGHOME=%s\nGPGKEY=%s\n' "$GNUPGHOME" "$GPGKEY" >>"$GITHUB_ENV"
else
    printf 'export GNUPGHOME=%q GPGKEY=%q\n' "$GNUPGHOME" "$GPGKEY"
fi
