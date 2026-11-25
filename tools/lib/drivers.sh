# shellcheck shell=bash
# Graphics driver setup, shared by blinux-install and blinux-drivers.
#
# Choices:
#   open         mesa and friends (packages/drivers-open.txt)
#   nvidia       NVIDIA proprietary, nvidia-open (packages/drivers-nvidia.txt)
#   nvidia-cuda  nvidia plus CUDA (packages/cuda.txt)
#
# For the NVIDIA choices this also:
#   - adds nvidia_drm.modeset=1 to the kernel command line, or GDM's udev rule
#     quietly turns Wayland off
#   - loads the nvidia modules early (mkinitcpio.conf.d drop-in)
#   - installs a pacman hook that rebuilds the initramfs on driver/kernel updates
# Switching back to "open" undoes all three.
#
# All paths are relative to $ROOT, so the installer can work on /mnt.

NVIDIA_CMDLINE="nvidia_drm.modeset=1"
NVIDIA_MKINITCPIO=/etc/mkinitcpio.conf.d/20-blinux-nvidia.conf
NVIDIA_HOOK=/etc/pacman.d/hooks/90-blinux-nvidia.hook
SDBOOT_ENTRIES=/boot/loader/entries
GRUB_DEFAULTS=/etc/default/grub

graphics_valid() {
    case "$1" in open | nvidia | nvidia-cuda) return 0 ;; *) return 1 ;; esac
}

# graphics_packages CHOICE: packages for a graphics choice
graphics_packages() {
    case "$1" in
        open) read_list "$(list_file drivers-open)" ;;
        nvidia) read_list "$(list_file drivers-nvidia)" ;;
        nvidia-cuda) read_list "$(list_file drivers-nvidia)" "$(list_file cuda)" ;;
        *) die "unknown graphics choice: $1" ;;
    esac
}

# graphics_describe CHOICE: a sentence to read aloud
graphics_describe() {
    case "$1" in
        open) echo "open source drivers" ;;
        nvidia) echo "NVIDIA proprietary drivers" ;;
        nvidia-cuda) echo "NVIDIA proprietary drivers with CUDA" ;;
    esac
}

# cmdline_add PARAM / cmdline_remove PARAM: edit the kernel command line of
# every Blinux systemd-boot entry, or GRUB's defaults. Idempotent.
cmdline_add() {
    local param="$1" entry grub
    shopt -s nullglob
    for entry in "$(rootpath "$SDBOOT_ENTRIES")"/blinux*.conf; do
        grep -Eq "^options.*(^| )${param}( |$)" "$entry" && continue
        run sed -i "s|^options .*|& ${param}|" "$entry"
    done
    shopt -u nullglob
    grub="$(rootpath "$GRUB_DEFAULTS")"
    if [[ -f "$grub" ]] && ! grep -Eq "^GRUB_CMDLINE_LINUX_DEFAULT=.*${param}" "$grub"; then
        run sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 ${param}\"|" "$grub"
        GRUB_CHANGED=1
    fi
}

cmdline_remove() {
    local param="$1" entry grub
    shopt -s nullglob
    for entry in "$(rootpath "$SDBOOT_ENTRIES")"/blinux*.conf; do
        run sed -i "s| ${param}||g" "$entry"
    done
    shopt -u nullglob
    grub="$(rootpath "$GRUB_DEFAULTS")"
    if [[ -f "$grub" ]] && grep -q "${param}" "$grub"; then
        run sed -i "s| ${param}||g" "$grub"
        GRUB_CHANGED=1
    fi
}

# chroot_run CMD...: run CMD in $ROOT (arch-chroot), or directly when ROOT=/.
chroot_run() {
    if [[ "$ROOT" == / ]]; then
        run "$@"
    else
        run arch-chroot "$ROOT" "$@"
    fi
}

write_nvidia_files() {
    write_file "$NVIDIA_MKINITCPIO" <<'EOF'
# Written by Blinux (blinux-drivers). Load NVIDIA's modules early so the
# display comes up with kernel modesetting and GNOME stays on Wayland.
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
    write_file "$NVIDIA_HOOK" <<'EOF'
# Written by Blinux (blinux-drivers): rebuild the initramfs whenever the NVIDIA
# driver or the kernel changes, so the early-loaded modules always match.
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = nvidia-open
Target = nvidia-utils
Target = linux

[Action]
Description = Rebuilding initramfs for the NVIDIA driver...
Depends = mkinitcpio
When = PostTransaction
NeedsTargets
Exec = /usr/bin/mkinitcpio -P
EOF
}

# apply_graphics CHOICE: configure (but don't install packages for) CHOICE.
apply_graphics() {
    local choice="$1"
    GRUB_CHANGED=0
    case "$choice" in
        nvidia | nvidia-cuda)
            write_nvidia_files
            cmdline_add "$NVIDIA_CMDLINE"
            ;;
        open)
            remove_file "$NVIDIA_MKINITCPIO"
            remove_file "$NVIDIA_HOOK"
            cmdline_remove "$NVIDIA_CMDLINE"
            ;;
        *) die "unknown graphics choice: $choice" ;;
    esac
    if [[ "$GRUB_CHANGED" == 1 ]]; then
        chroot_run grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

# current_graphics: what the system at $ROOT is set up for
current_graphics() {
    if [[ -f "$(rootpath "$NVIDIA_MKINITCPIO")" ]]; then
        if [[ -d "$(rootpath /opt/cuda)" ]]; then echo nvidia-cuda; else echo nvidia; fi
    else
        echo open
    fi
}
