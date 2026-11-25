#!/usr/bin/env bash
# CI helper: free space on a GitHub-hosted Ubuntu runner. The ISO build and
# clean-chroot package builds need more than the default free disk.
set -euo pipefail
before=$(df --output=avail -BG / | tail -1)
sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup \
    /usr/share/swift /usr/local/share/boost /opt/hostedtoolcache/CodeQL
sudo docker image prune --all --force >/dev/null || true
after=$(df --output=avail -BG / | tail -1)
echo "free disk: $before -> $after"
