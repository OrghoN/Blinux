#!/usr/bin/env bats
# blinux-dotfiles with a fixture repository laid out like OrghoN/.dotfiles.

load helpers

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    SRC="$BATS_TEST_TMPDIR/dotfiles-src"
    cp -r "$FIXTURES/dotfiles" "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" add -A
    git -C "$SRC" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
    export OMZ_SYSTEM="$BATS_TEST_TMPDIR/oh-my-zsh"
    export P10K_SYSTEM="$BATS_TEST_TMPDIR/powerlevel10k"
    mkdir -p "$OMZ_SYSTEM/custom" "$P10K_SYSTEM"
    touch "$OMZ_SYSTEM/oh-my-zsh.sh"
}

dotfiles() { run "$TOOLS/blinux-dotfiles" --as-user --url "$SRC" "$@"; }

@test "links dotfiles, init.el and zsh snippets like the dotfiles README" {
    dotfiles
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.zshrc")" = "$HOME/.dotfiles/.zshrc" ]
    [ "$(readlink "$HOME/.p10k.zsh")" = "$HOME/.dotfiles/.p10k.zsh" ]
    [ "$(readlink "$HOME/.emacs.d/init.el")" = "$HOME/.dotfiles/init.el" ]
    [ "$(readlink "$HOME/.oh-my-zsh/custom/zsh_aliases.zsh")" = "$HOME/.dotfiles/zsh_aliases.zsh" ]
    [ "$(readlink "$HOME/.oh-my-zsh/custom/zoxide.zsh")" = "$HOME/.dotfiles/custom/zoxide.zsh" ]
    [ ! -e "$HOME/.oh-my-zsh/custom/.p10k.zsh" ]
    [ ! -e "$HOME/.git" ]
}

@test "sets up ~/.oh-my-zsh with powerlevel10k, which those dotfiles expect" {
    dotfiles
    [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]
    [ "$(readlink "$HOME/.oh-my-zsh/custom/themes/powerlevel10k")" = "$P10K_SYSTEM" ]
    grep -q "^export dotfiles=$HOME/.dotfiles$" "$HOME/.zshenv"
}

@test "existing files are backed up, not overwritten" {
    echo "my old zshrc" >"$HOME/.zshrc"
    dotfiles
    [ "$(cat "$HOME/.zshrc.blinux-backup")" = "my old zshrc" ]
    [[ "$output" == *"Moved your old .zshrc to .zshrc.blinux-backup."* ]]
}

@test "running twice is harmless" {
    dotfiles
    dotfiles
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating the dotfiles"* ]]
    [ ! -e "$HOME/.zshrc.blinux-backup" ]
    [ "$(grep -c '^export dotfiles=' "$HOME/.zshenv")" -eq 1 ]
}

@test "a repository with its own bootstrap script uses it instead" {
    printf '#!/bin/sh\necho "bootstrap ran with dotfiles=$dotfiles" >"$HOME/bootstrap.log"\n' >"$SRC/install.sh"
    chmod +x "$SRC/install.sh"
    git -C "$SRC" add -A
    git -C "$SRC" -c user.name=test -c user.email=test@example.invalid commit -qm bootstrap
    dotfiles
    [ "$status" -eq 0 ]
    grep -q "bootstrap ran with dotfiles=$HOME/.dotfiles" "$HOME/bootstrap.log"
    [ ! -L "$HOME/.zshrc" ]
}

@test "refuses to set up dotfiles for root" {
    run "$TOOLS/blinux-dotfiles" --user root
    [ "$status" -ne 0 ]
    [[ "$output" == *"not root"* ]]
}

@test "the installer path runs as the user inside the new system" {
    run env DRY_RUN=1 "$TOOLS/blinux-dotfiles" --root /mnt --user tester --url https://example.invalid/d.git
    [[ "$output" == *"arch-chroot /mnt runuser -l tester -c blinux-dotfiles"* ]]
    [[ "$output" == *"--as-user"* ]]
}
