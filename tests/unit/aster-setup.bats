#!/usr/bin/env bats
# blinux-aster-setup: DECtalk is proprietary, so nothing happens without a yes.

load helpers

@test "explains the licence and does nothing by default" {
    setup_stubs makepkg
    run bash -c "echo '' | '$TOOLS/blinux-aster-setup'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DECtalk is proprietary software"* ]]
    [[ "$output" == *"Blinux does not distribute it"* ]]
    [[ "$output" == *"Nothing was changed."* ]]
    [ ! -s "$STUB_LOG" ]
}

@test "with yes, builds DECtalk then Emacspeak's DECtalk server, in that order" {
    setup_stubs makepkg
    run bash -c "echo yes | BLINUX_RECIPES='$REPO/tools/share/local-pkgbuilds' '$TOOLS/blinux-aster-setup'"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'makepkg --syncdeps --install' "$STUB_LOG")" -eq 2 ]
}

@test "the recipes are local-only: neither is in pkgbuilds/ or the stack lists" {
    [ ! -d "$REPO/pkgbuilds/dectalk" ]
    ! grep -rqx 'dectalk' "$REPO/packages"
    grep -q 'LicenseRef-Fonix-proprietary' "$REPO/tools/share/local-pkgbuilds/dectalk/PKGBUILD"
}
