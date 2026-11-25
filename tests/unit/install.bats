#!/usr/bin/env bats
# blinux-install in dry-run mode: every command is printed, nothing runs.

load helpers

@test "minimal UEFI install: GPT with an ESP, systemd-boot, no GRUB" {
    install_dry_run "$FIXTURES/install/minimal.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sgdisk -n1:0:+1G -t1:ef00"* ]]
    [[ "$output" == *"mkfs.fat -F 32 -n EFI /dev/vda1"* ]]
    [[ "$output" == *"bootctl install --esp-path=/boot"* ]]
    [[ "$output" != *grub-install* ]]
    [[ "$output" == *"Installation complete."* ]]
}

@test "every step is announced as 'Step N of 11'" {
    install_dry_run "$FIXTURES/install/minimal.json"
    [ "$(grep -c '^Step [0-9]* of 11:' <<<"$output")" -eq 11 ]
}

@test "BIOS install: bios_grub partition, separate /boot, GRUB" {
    install_dry_run "$FIXTURES/install/bios.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-t1:ef02"* ]]
    [[ "$output" == *"grub-install --target=i386-pc /dev/vda"* ]]
    [[ "$output" == *"grub-mkconfig -o /boot/grub/grub.cfg"* ]]
    [[ "$output" != *bootctl* ]]
}

@test "encrypted install formats LUKS2 and writes the encrypt hook" {
    install_dry_run "$FIXTURES/install/encrypted.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cryptsetup luksFormat --type luks2"* ]]
    [[ "$output" == *"mkfs.ext4 -F -L blinux /dev/mapper/blinuxroot"* ]]
    [[ "$output" == *"write /mnt/etc/mkinitcpio.conf.d/10-blinux-encrypt.conf"* ]]
    [[ "$output" == *"cryptsetup close blinuxroot"* ]]
}

@test "the passphrase never appears in the output" {
    install_dry_run "$FIXTURES/install/encrypted.json"
    [[ "$output" != *blinux-test-passphrase* ]]
    [[ "$output" != *"blinux-test "* ]]
}

@test "console speech is only enabled when asked for" {
    install_dry_run "$FIXTURES/install/console-speech.json"
    [[ "$output" == *"blinux-console-speech enable --root /mnt"* ]]
    install_dry_run "$FIXTURES/install/minimal.json"
    [[ "$output" != *blinux-console-speech* ]]
}

@test "the user gets zsh, wheel, and root is locked" {
    install_dry_run "$FIXTURES/install/minimal.json"
    [[ "$output" == *"useradd -m -G wheel -s /usr/bin/zsh tester"* ]]
    [[ "$output" == *"passwd --lock root"* ]]
}

@test "GDM, NetworkManager and Bluetooth are enabled; espeakup is not" {
    install_dry_run "$FIXTURES/install/minimal.json"
    [[ "$output" == *"systemctl enable gdm.service NetworkManager.service bluetooth.service"* ]]
    [[ "$output" != *"enable espeakup"* ]]
}

@test "base install uses the ISO's offline cache when present" {
    OFFLINE_REPO="$BATS_TEST_TMPDIR/offline-repo"
    mkdir -p "$OFFLINE_REPO"
    install_dry_run "$FIXTURES/install/minimal.json"
    [[ "$output" == *"Using the packages on the install medium"* ]]
    [[ "$output" == *"pacstrap -C "*"-K /mnt blinux-base"* ]]
}

@test "microcode follows the config" {
    install_dry_run "$FIXTURES/install/all-stacks.json"
    [[ "$output" == *"pacstrap -K /mnt blinux-base intel-ucode"* ]]
    install_dry_run "$FIXTURES/install/nvidia-cuda.json"
    [[ "$output" == *"blinux-base amd-ucode"* ]]
    install_dry_run "$FIXTURES/install/minimal.json"
    [[ "$output" != *ucode* ]]
}

@test "all stacks online: one pacman transaction with every meta-package" {
    install_dry_run "$FIXTURES/install/all-stacks.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pacman -Syu --noconfirm --needed blinux-aster blinux-docs blinux-hep blinux-ml"* ]]
    [[ "$output" == *"blinux-dotfiles --root /mnt --user tester --url http://10.0.2.2:8000/dotfiles.git"* ]]
}

@test "NVIDIA + CUDA + ML installs the CUDA stack and NVIDIA config" {
    install_dry_run "$FIXTURES/install/nvidia-cuda.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvidia-open"*"cuda"*"cudnn"*"python-pytorch-cuda blinux-ml blinux-ml-cuda"* ]]
    [[ "$output" == *"write /mnt/etc/mkinitcpio.conf.d/20-blinux-nvidia.conf"* ]]
    [[ "$output" == *"write /mnt/etc/pacman.d/hooks/90-blinux-nvidia.hook"* ]]
}

@test "offline: proprietary drivers and stacks are skipped with the catch-up command" {
    OFFLINE=1 ONLINE=0
    install_dry_run "$FIXTURES/install/offline.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"There is no network connection, so these are skipped"* ]]
    [[ "$output" == *"sudo pacman -S nvidia-open nvidia-utils nvidia-settings blinux-hep"* ]]
    [[ "$output" != *"pacman -Syu"* ]]
    [[ "$output" == *"open source drivers stay in use"* ]]
    [[ "$output" != *20-blinux-nvidia.conf* ]]
}

@test "invalid configs are rejected before anything happens" {
    local f
    for f in "$FIXTURES"/install/invalid/*.json; do
        install_dry_run "$f"
        [ "$status" -ne 0 ]
        [[ "$output" != *"Step 1"* ]]
    done
}

@test "interactive: answers become the same config" {
    local cfg="$BATS_TEST_TMPDIR/cfg.json"
    run bash -c "printf '%s\n' 2 erase erase no '' tester pw pw '' '' yes 3 no no yes yes no | \
        BLINUX_ONLINE=1 LSBLK_FILE='$FIXTURES/hw/lsblk.json' LIVE_DEVICE=/dev/sda \
        LSPCI_FILE='$FIXTURES/hw/lspci-hybrid-intel-nvidia.txt' CPUINFO_FILE='$FIXTURES/hw/cpuinfo-intel.txt' \
        '$TOOLS/blinux-install' --dry-run --save-config '$cfg'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Option 1 of 2: /dev/nvme0n1, 1.0 terabytes"* ]]
    [[ "$output" == *"The suggestion is option 2."* ]]
    [ "$(jq -r .disk "$cfg")" = /dev/sdb ]
    [ "$(jq -r .graphics "$cfg")" = nvidia-cuda ]
    [ "$(jq -r .microcode "$cfg")" = intel ]
    [ "$(jq -c .stacks "$cfg")" = '["hep","ml"]' ]
    [ "$(jq -r .username "$cfg")" = tester ]
    [ "$(stat -c %a "$cfg")" = 600 ]
}

@test "interactive: not typing 'erase' twice stops with nothing changed" {
    run bash -c "printf '%s\n' 1 erase nope | LSBLK_FILE='$FIXTURES/hw/lsblk.json' LIVE_DEVICE=/dev/sda \
        BLINUX_ONLINE=1 '$TOOLS/blinux-install' --dry-run"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not confirmed. Nothing was changed."* ]]
    [[ "$output" != *"Step 1"* ]]
}

@test "interactive: a bad user name is explained and asked again" {
    local cfg="$BATS_TEST_TMPDIR/cfg.json"
    run bash -c "printf '%s\n' 1 erase erase no no Root tester pw pw '' '' yes 1 no no no no no | \
        BLINUX_ONLINE=1 LSBLK_FILE='$FIXTURES/hw/lsblk.json' LIVE_DEVICE=/dev/sda \
        LSPCI_FILE='$FIXTURES/hw/lspci-amd.txt' CPUINFO_FILE='$FIXTURES/hw/cpuinfo-amd.txt' \
        '$TOOLS/blinux-install' --dry-run --save-config '$cfg'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"That user name can't be used."* ]]
    [ "$(jq -r .username "$cfg")" = tester ]
    [ "$(jq -r .graphics "$cfg")" = open ]
}
