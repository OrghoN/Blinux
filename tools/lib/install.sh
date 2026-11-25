# shellcheck shell=bash
# The installation steps. blinux-install collects answers (interactively or
# from --config) into one JSON config, then runs install_system.
#
# Long-running commands send their output to $LOG_FILE instead of the screen:
# thousands of pacman lines read out by speakup would bury what matters. A
# short spoken line marks each step, a "still working" line repeats every
# minute, and on failure the last lines of the log are read out.

MNT="${MNT:-/mnt}"
OFFLINE_REPO="${OFFLINE_REPO:-/opt/blinux/offline-repo}"
BLINUX_SERVER="${BLINUX_SERVER:-https://github.com/OrghoN/Blinux/releases/download/repo}"
STEP=0
STEPS=11

# ---------------------------------------------------------------- config

# cfg KEY [DEFAULT]: read a value from the loaded config (jq path syntax).
cfg() {
    local value
    value="$(jq -r "$1 // empty" <<<"$CONFIG")"
    printf '%s\n' "${value:-${2:-}}"
}

# load_config FILE|-: read, validate and normalise the install config.
load_config() {
    CONFIG="$(jq -c . "$1")" || die "the config is not valid JSON: $1"
    validate_config
}

validate_config() {
    local disk graphics user host stacks
    disk="$(cfg .disk)"
    [[ -n "$disk" ]] || die "config: disk is required"
    user="$(cfg .username)"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "config: username must be lowercase letters, digits, - or _"
    [[ "$user" != root ]] || die "config: username can't be root"
    [[ -n "$(cfg .password)" ]] || die "config: password is required"
    host="$(cfg .hostname blinux)"
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "config: invalid hostname"
    if [[ "$(cfg .encrypt false)" == true ]]; then
        [[ -n "$(cfg .passphrase)" ]] || die "config: encrypt is true but passphrase is missing"
    fi
    graphics="$(cfg .graphics open)"
    mapfile -t stacks < <(jq -r '.stacks // [] | .[]' <<<"$CONFIG")
    validate_choices "$graphics" "${stacks[@]}"
    case "$(cfg .firmware auto)" in auto | uefi | bios) ;; *) die "config: firmware must be auto, uefi or bios" ;; esac
    case "$(cfg .microcode auto)" in auto | intel | amd | none) ;; *) die "config: microcode must be auto, intel, amd or none" ;; esac
}

# ---------------------------------------------------------------- narration

step() {
    STEP=$((STEP + 1))
    say "Step $STEP of $STEPS: $*"
}

# quiet CMD...: run CMD with its output going to the log. While it runs, say
# "Still working" every HEARTBEAT seconds. On failure, read out the log tail.
quiet() {
    {
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    } >>"$LOG_FILE"
    if [[ "$DRY_RUN" == 1 ]]; then
        printf 'DRY-RUN:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$! waited=0 status=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if ((waited % ${HEARTBEAT:-60} == 0)); then
            say "Still working, $((waited / 60)) minutes so far."
        fi
    done
    wait "$pid" || status=$?
    if ((status != 0)); then
        say "That step failed. The last lines of the log say:"
        tail -n 5 "$LOG_FILE"
        say "The full log is in $LOG_FILE."
        return "$status"
    fi
}

in_target() {
    quiet arch-chroot "$MNT" "$@"
}

# ---------------------------------------------------------------- steps

resolve_firmware() {
    FIRMWARE="$(cfg .firmware auto)"
    [[ "$FIRMWARE" == auto ]] && FIRMWARE="$(boot_mode)"
    MICROCODE="$(cfg .microcode auto)"
    [[ "$MICROCODE" == auto ]] && MICROCODE="$(cpu_vendor)"
    MICROCODE_PKG="$(microcode_package "$MICROCODE")"
}

partition_disk() {
    local disk
    disk="$(cfg .disk)"
    step "erasing and partitioning $disk."
    quiet wipefs --all --force "$disk"
    quiet sgdisk --zap-all "$disk"
    if [[ "$FIRMWARE" == uefi ]]; then
        quiet sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8304 -c2:blinux "$disk"
        BOOT_PART="$(partition_path "$disk" 1)"
        ROOT_PART="$(partition_path "$disk" 2)"
    else
        quiet sgdisk -n1:0:+1M -t1:ef02 -c1:bios -n2:0:+1G -t2:8300 -c2:boot \
            -n3:0:0 -t3:8304 -c3:blinux "$disk"
        BOOT_PART="$(partition_path "$disk" 2)"
        ROOT_PART="$(partition_path "$disk" 3)"
    fi
    quiet partprobe "$disk"
    runcmd udevadm settle
}

format_and_mount() {
    step "formatting and mounting."
    ROOT_DEV="$ROOT_PART"
    if [[ "$(cfg .encrypt false)" == true ]]; then
        say "Setting up disk encryption."
        local pass
        pass="$(cfg .passphrase)"
        if [[ "$DRY_RUN" == 1 ]]; then
            runcmd cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$ROOT_PART"
            runcmd cryptsetup open --key-file=- "$ROOT_PART" blinuxroot
        else
            # Not through quiet(): background jobs get /dev/null as stdin, and
            # the passphrase has to reach cryptsetup on stdin.
            printf '+ cryptsetup luksFormat %q\n' "$ROOT_PART" >>"$LOG_FILE"
            printf '%s' "$pass" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$ROOT_PART" >>"$LOG_FILE" 2>&1 ||
                die "Setting up encryption failed. See $LOG_FILE."
            printf '%s' "$pass" | cryptsetup open --key-file=- "$ROOT_PART" blinuxroot >>"$LOG_FILE" 2>&1 ||
                die "Unlocking the new encrypted disk failed. See $LOG_FILE."
        fi
        ROOT_DEV=/dev/mapper/blinuxroot
    fi
    quiet mkfs.ext4 -F -L blinux "$ROOT_DEV"
    if [[ "$FIRMWARE" == uefi ]]; then
        quiet mkfs.fat -F 32 -n EFI "$BOOT_PART"
    else
        quiet mkfs.ext4 -F -L boot "$BOOT_PART"
    fi
    runcmd mount "$ROOT_DEV" "$MNT"
    runcmd mount --mkdir "$BOOT_PART" "$MNT/boot"
}

write_pacman_confs() {
    # Offline config: only the ISO's cache of the base stack.
    OFFLINE_CONF="${TMPDIR:-/tmp}/blinux-offline-pacman.conf"
    if [[ "$DRY_RUN" != 1 ]]; then
        cat >"$OFFLINE_CONF" <<EOF
[options]
Architecture = auto
ParallelDownloads = 5
# Packages come from the ISO itself, which is verified by its checksum and
# signature, so the local cache is trusted as-is.
SigLevel = Optional TrustAll

[blinux-offline]
Server = file://$OFFLINE_REPO
EOF
    fi
}

install_base() {
    step "installing the base system. This takes several minutes."
    local pkgs=(blinux-base)
    [[ -n "$MICROCODE_PKG" ]] && pkgs+=("$MICROCODE_PKG")
    mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$(list_file drivers-open)")
    if [[ -d "$OFFLINE_REPO" ]]; then
        say "Using the packages on the install medium, so no network is needed."
        write_pacman_confs
        quiet pacstrap -C "$OFFLINE_CONF" -K "$MNT" "${pkgs[@]}"
    else
        say "Downloading packages from the network."
        quiet pacstrap -K "$MNT" "${pkgs[@]}"
    fi
    # The installed system gets the normal Arch repos plus [blinux].
    write_file /etc/pacman.d/blinux.conf <<EOF
# The Blinux package repository (installed by blinux-install).
# TODO(v0.1.0): switch to "SigLevel = Required" once blinux-keyring ships the
# signing key; until then packages are verified only by HTTPS.
[blinux]
SigLevel = Optional TrustAll
Server = $BLINUX_SERVER
EOF
    local conf
    conf="$(rootpath /etc/pacman.conf)"
    if [[ "$DRY_RUN" == 1 ]] || ! grep -q '^Include = /etc/pacman.d/blinux.conf' "$conf" 2>/dev/null; then
        if [[ "$DRY_RUN" == 1 ]]; then
            say "DRY-RUN: add [blinux] to $conf"
        else
            printf '\nInclude = /etc/pacman.d/blinux.conf\n' >>"$conf"
        fi
    fi
}

configure_system() {
    step "setting the time zone, language and host name."
    local tz locale keymap host
    tz="$(cfg .timezone UTC)"
    locale="$(cfg .locale en_US.UTF-8)"
    keymap="$(cfg .keymap us)"
    host="$(cfg .hostname blinux)"
    if [[ "$DRY_RUN" != 1 ]]; then
        genfstab -U "$MNT" >>"$MNT/etc/fstab"
    else
        say "DRY-RUN: genfstab -U $MNT"
    fi
    in_target ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
    in_target hwclock --systohc
    in_target sed -i "s/^#\\(${locale//./\\.} \\)/\\1/" /etc/locale.gen
    in_target locale-gen
    write_file /etc/locale.conf <<<"LANG=$locale"
    write_file /etc/vconsole.conf <<<"KEYMAP=$keymap"
    write_file /etc/hostname <<<"$host"
    write_file /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $host.localdomain $host
EOF
}

create_user() {
    local user
    user="$(cfg .username)"
    step "creating the user $user, with zsh as the shell."
    in_target useradd -m -G wheel -s /usr/bin/zsh "$user"
    if [[ "$DRY_RUN" == 1 ]]; then
        runcmd arch-chroot "$MNT" chpasswd
    else
        printf '%s:%s\n' "$user" "$(cfg .password)" | arch-chroot "$MNT" chpasswd
    fi
    # No root password: administration goes through sudo (wheel).
    in_target passwd --lock root
}

configure_boot() {
    step "setting up the boot loader."
    local options
    if [[ "$(cfg .encrypt false)" == true ]]; then
        local uuid
        if [[ "$DRY_RUN" == 1 ]]; then uuid=DRY-RUN-UUID; else uuid="$(blkid -s UUID -o value "$ROOT_PART")"; fi
        options="cryptdevice=UUID=$uuid:blinuxroot root=/dev/mapper/blinuxroot rw"
        write_file /etc/mkinitcpio.conf.d/10-blinux-encrypt.conf <<'EOF'
# Written by blinux-install: unlock the encrypted root at boot.
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)
EOF
    else
        local uuid
        if [[ "$DRY_RUN" == 1 ]]; then uuid=DRY-RUN-UUID; else uuid="$(blkid -s UUID -o value "$ROOT_DEV")"; fi
        options="root=UUID=$uuid rw"
    fi

    if [[ "$FIRMWARE" == uefi ]]; then
        in_target bootctl install --esp-path=/boot
        write_file /boot/loader/loader.conf <<'EOF'
default blinux.conf
timeout 3
editor no
EOF
        write_file /boot/loader/entries/blinux.conf <<EOF
title   Blinux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options $options
EOF
    else
        in_target grub-install --target=i386-pc "$(cfg .disk)"
        in_target sed -i "s|^GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"${options% rw}\"|" /etc/default/grub
        in_target sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|' /etc/default/grub
    fi
}

install_network_extras() {
    local graphics stacks pkgs
    graphics="$(cfg .graphics open)"
    mapfile -t stacks < <(jq -r '.stacks // [] | .[]' <<<"$CONFIG")
    mapfile -t pkgs < <(network_packages "$graphics" "${stacks[@]}")
    [[ "$(cfg .broadcom_wl false)" == true ]] && pkgs+=(broadcom-wl)
    step "installing drivers and optional stacks."
    if ((${#pkgs[@]} == 0)); then
        say "Nothing extra was chosen."
        return 0
    fi
    if ! network_online; then
        say "There is no network connection, so these are skipped: ${pkgs[*]}."
        say "After the first boot, connect to a network and run: sudo pacman -S ${pkgs[*]}"
        SKIPPED_PACKAGES=("${pkgs[@]}")
        return 0
    fi
    say "Downloading: ${pkgs[*]}. Large stacks can take a long time."
    in_target pacman -Syu --noconfirm --needed "${pkgs[@]}"
}

configure_graphics() {
    local graphics
    graphics="$(cfg .graphics open)"
    step "configuring $(graphics_describe "$graphics")."
    if [[ "$graphics" != open && "${#SKIPPED_PACKAGES[@]}" -gt 0 ]]; then
        say "The NVIDIA driver wasn't installed, so the open source drivers stay in use."
        say "Run sudo blinux-drivers after connecting to a network to switch."
        return 0
    fi
    ROOT="$MNT" apply_graphics "$graphics"
    write_file /etc/blinux/graphics <<<"$graphics"
}

finish_system() {
    step "building the startup image and enabling services."
    in_target mkinitcpio -P
    [[ "$FIRMWARE" == bios ]] && in_target grub-mkconfig -o /boot/grub/grub.cfg
    in_target systemctl enable gdm.service NetworkManager.service bluetooth.service
    if [[ "$(cfg .console_speech false)" == true ]]; then
        say "Turning on console speech."
        runcmd blinux-console-speech enable --root "$MNT"
    fi
    # Carry the live system's unmuted mixer levels over, so the first boot is never silent.
    if [[ "$DRY_RUN" != 1 ]]; then
        alsactl store >>"$LOG_FILE" 2>&1 || true
        if [[ -f /var/lib/alsa/asound.state ]]; then
            install -Dm644 /var/lib/alsa/asound.state "$MNT/var/lib/alsa/asound.state"
        fi
    else
        say "DRY-RUN: copy the ALSA mixer state"
    fi
}

setup_dotfiles() {
    step "setting up dotfiles."
    if [[ "$(cfg .dotfiles.enabled false)" != true ]]; then
        say "Skipped, as chosen."
        return 0
    fi
    if ! network_online; then
        say "There is no network, so the dotfiles weren't cloned. Run blinux-dotfiles after the first boot."
        return 0
    fi
    runcmd blinux-dotfiles --root "$MNT" --user "$(cfg .username)" --url "$(cfg .dotfiles.url https://github.com/OrghoN/.dotfiles)"
}

unmount_all() {
    step "finishing up."
    runcmd sync
    runcmd umount -R "$MNT"
    if [[ "$(cfg .encrypt false)" == true ]]; then
        runcmd cryptsetup close blinuxroot
    fi
}

install_system() {
    SKIPPED_PACKAGES=()
    resolve_firmware
    say "Installing Blinux on $(cfg .disk). There are $STEPS steps."
    partition_disk
    format_and_mount
    install_base
    configure_system
    create_user
    configure_boot
    install_network_extras
    configure_graphics
    finish_system
    setup_dotfiles
    unmount_all
    say "Installation complete."
    if ((${#SKIPPED_PACKAGES[@]})); then
        say "Remember to install the skipped packages later: ${SKIPPED_PACKAGES[*]}"
    fi
}
