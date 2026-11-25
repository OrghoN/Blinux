#!/usr/bin/env bats
# blinux-console-speech against a temporary root.

load helpers

setup() {
    R="$BATS_TEST_TMPDIR/root"
    mkdir -p "$R/usr/share"
    cp -r "$REPO/config/usr/share/blinux" "$R/usr/share/"
    setup_stubs systemctl
}

@test "enable writes the PulseAudio and espeakup drop-ins and enables espeakup" {
    run "$TOOLS/blinux-console-speech" enable --root "$R"
    [ "$status" -eq 0 ]
    grep -q 'module-native-protocol-unix auth-anonymous=1 socket=/tmp/blinux-pulse.sock' \
        "$R/etc/pulse/default.pa.d/10-blinux-espeakup.pa"
    grep -q 'PULSE_SERVER=unix:/tmp/blinux-pulse.sock' \
        "$R/etc/systemd/system/espeakup.service.d/10-blinux-pulse.conf"
    grep -q "systemctl --root=$R enable espeakup.service" "$STUB_LOG"
}

@test "status reports on and off" {
    run "$TOOLS/blinux-console-speech" status --root "$R"
    [ "$output" = "Console speech is off." ]
    "$TOOLS/blinux-console-speech" enable --root "$R"
    run "$TOOLS/blinux-console-speech" status --root "$R"
    [ "$output" = "Console speech is on." ]
}

@test "enable is idempotent and disable removes everything" {
    "$TOOLS/blinux-console-speech" enable --root "$R"
    "$TOOLS/blinux-console-speech" enable --root "$R"
    run "$TOOLS/blinux-console-speech" disable --root "$R"
    [ "$status" -eq 0 ]
    [ ! -e "$R/etc/pulse/default.pa.d/10-blinux-espeakup.pa" ]
    [ ! -e "$R/etc/systemd/system/espeakup.service.d/10-blinux-pulse.conf" ]
    grep -q "disable espeakup.service" "$STUB_LOG"
}

@test "on a running system it restarts espeakup with --now" {
    run env DRY_RUN=1 BLINUX_SHARE="$REPO/config/usr/share/blinux" "$TOOLS/blinux-console-speech" enable
    [[ "$output" == *"systemctl enable --now espeakup.service"* ]]
    [[ "$output" == *"systemctl daemon-reload"* ]]
}
