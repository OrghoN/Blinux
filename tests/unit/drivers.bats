#!/usr/bin/env bats
# blinux-drivers and the shared driver logic, against a temporary root.

load helpers

setup() {
    R="$BATS_TEST_TMPDIR/root"
    mkdir -p "$R/boot/loader/entries" "$R/etc"
    printf 'title Blinux\nlinux /vmlinuz-linux\noptions root=UUID=abc rw\n' >"$R/boot/loader/entries/blinux.conf"
    setup_stubs arch-chroot pacman
    export LSPCI_FILE="$FIXTURES/hw/lspci-nvidia-turing.txt"
}

drivers() { run "$TOOLS/blinux-drivers" "$@" --root "$R" --yes; }

@test "switching to NVIDIA keeps GNOME on Wayland and loads modules early" {
    drivers nvidia --no-packages
    [ "$status" -eq 0 ]
    grep -q '^options root=UUID=abc rw nvidia_drm.modeset=1$' "$R/boot/loader/entries/blinux.conf"
    grep -q 'MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' "$R/etc/mkinitcpio.conf.d/20-blinux-nvidia.conf"
    grep -q 'Exec = /usr/bin/mkinitcpio -P' "$R/etc/pacman.d/hooks/90-blinux-nvidia.hook"
    [ "$(cat "$R/etc/blinux/graphics")" = nvidia ]
    grep -q "arch-chroot $R mkinitcpio -P" "$STUB_LOG"
}

@test "the kernel parameter is added only once" {
    drivers nvidia --no-packages
    drivers nvidia-cuda --no-packages
    [ "$(grep -o nvidia_drm.modeset=1 "$R/boot/loader/entries/blinux.conf" | wc -l)" -eq 1 ]
}

@test "switching back to open undoes every NVIDIA change" {
    drivers nvidia --no-packages
    drivers open --no-packages
    [ "$status" -eq 0 ]
    grep -q '^options root=UUID=abc rw$' "$R/boot/loader/entries/blinux.conf"
    [ ! -e "$R/etc/mkinitcpio.conf.d/20-blinux-nvidia.conf" ]
    [ ! -e "$R/etc/pacman.d/hooks/90-blinux-nvidia.hook" ]
    [ "$(cat "$R/etc/blinux/graphics")" = open ]
}

@test "GRUB systems get the parameter in /etc/default/grub and a regenerated config" {
    rm "$R/boot/loader/entries/blinux.conf"
    mkdir -p "$R/etc/default"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\nGRUB_CMDLINE_LINUX=""\n' >"$R/etc/default/grub"
    drivers nvidia --no-packages
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"$' "$R/etc/default/grub"
    grep -q "arch-chroot $R grub-mkconfig -o /boot/grub/grub.cfg" "$STUB_LOG"
}

@test "status and no-op switches" {
    run "$TOOLS/blinux-drivers" --status --root "$R"
    [ "$output" = "This system uses open source drivers." ]
    drivers open
    [[ "$output" == *"Nothing to do"* ]]
}

@test "packages: NVIDIA + CUDA installs, back to open removes them" {
    drivers nvidia-cuda
    grep -q "pacman --root $R -S --needed --noconfirm nvidia-open nvidia-utils nvidia-settings cuda cudnn" "$STUB_LOG"
}

@test "warns when the card is too old for nvidia-open" {
    LSPCI_FILE="$FIXTURES/hw/lspci-nvidia-pascal.txt" drivers nvidia --no-packages
    [[ "$output" == *"older than Turing"* ]]
}

@test "warns when there is no NVIDIA card at all" {
    LSPCI_FILE="$FIXTURES/hw/lspci-amd.txt" drivers nvidia --no-packages
    [[ "$output" == *"No NVIDIA graphics card was found"* ]]
}
