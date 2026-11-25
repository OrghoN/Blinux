#!/usr/bin/env bats
# The question helpers: plain lines in, plain lines out.

load helpers

setup() { load_libs; }

@test "choose reads every option with its number and returns the index" {
    run bash -c "source '$REPO/tools/lib/common.sh'; echo 2 | choose 'Pick one.' 1 apples pears plums"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Option 1 of 3: apples."* ]]
    [[ "$output" == *"Option 3 of 3: plums."* ]]
    [[ "$output" == *"You chose: pears."* ]]
    [ "${lines[-1]}" = 2 ]
}

@test "choose uses the default on Enter and re-asks on bad input" {
    run bash -c "source '$REPO/tools/lib/common.sh'; printf '9\nx\n\n' | choose 'Pick.' 3 a b c"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'That is not one of the options.' <<<"$output")" -eq 2 ]
    [ "${lines[-1]}" = 3 ]
}

@test "ask_yes_no accepts y, yes, n, no in any case, with a default" {
    local a
    for a in y Yes YES; do echo "$a" | ask_yes_no "Q?" no; done
    for a in n No NO; do ! echo "$a" | ask_yes_no "Q?" yes; done
    echo "" | ask_yes_no "Q?" yes
    ! echo "" | ask_yes_no "Q?" no
}

@test "ask_secret needs two matching, non-empty entries" {
    run bash -c "source '$REPO/tools/lib/common.sh'; printf '\n\na\nb\nsecret\nsecret\n' | ask_secret 'Password.'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"It can't be empty."* ]]
    [[ "$output" == *"They didn't match."* ]]
    [ "${lines[-1]}" = secret ]
}

@test "output has no colour codes or other escape sequences" {
    run bash -c "source '$REPO/tools/lib/common.sh'; echo 1 | choose 'Pick.' 1 a b 2>&1"
    ! grep -q $'\e' <<<"$output"
    install_dry_run "$FIXTURES/install/all-stacks.json"
    ! grep -q $'\e' <<<"$output"
}

@test "write_file and remove_file stay inside ROOT" {
    ROOT="$BATS_TEST_TMPDIR/r"
    write_file /etc/blinux/test <<<"hello"
    [ "$(cat "$ROOT/etc/blinux/test")" = hello ]
    remove_file /etc/blinux/test
    [ ! -e "$ROOT/etc/blinux/test" ]
}

@test "read_list drops comments and blank lines" {
    run read_list "$REPO/packages/microcode.txt"
    [ "$output" = "$(printf 'intel-ucode\namd-ucode')" ]
}
