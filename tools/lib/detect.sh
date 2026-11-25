# shellcheck shell=bash
# Hardware and environment detection for the Blinux installer and helpers.
#
# Every input can be replaced with a fixture file, so the unit tests can feed in
# recorded output from real machines:
#   LSPCI_FILE   output of `lspci -mm -nn`
#   CPUINFO_FILE /proc/cpuinfo
#   LSBLK_FILE   output of `lsblk -J -d -b -o NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,RO`
#   EFI_DIR      /sys/firmware/efi (present on UEFI boots)

_lspci() {
    if [[ -n "${LSPCI_FILE:-}" ]]; then cat "$LSPCI_FILE"; else lspci -mm -nn; fi
}

# boot_mode: "uefi" or "bios"
boot_mode() {
    if [[ -d "${EFI_DIR:-/sys/firmware/efi}" ]]; then echo uefi; else echo bios; fi
}

# cpu_vendor: "intel", "amd" or "unknown"
cpu_vendor() {
    local vendor
    vendor="$(awk -F': *' '/^vendor_id/ {print $2; exit}' "${CPUINFO_FILE:-/proc/cpuinfo}")"
    case "$vendor" in
        GenuineIntel) echo intel ;;
        AuthenticAMD) echo amd ;;
        *) echo unknown ;;
    esac
}

# microcode_package VENDOR: package name, or nothing for unknown CPUs
microcode_package() {
    case "$1" in
        intel) echo intel-ucode ;;
        amd) echo amd-ucode ;;
    esac
}

# gpus: one line per display controller: "<vendor> <turing+|legacy|-> <description>"
#   vendor is intel, amd, nvidia or other. The second field only matters for
#   NVIDIA: nvidia-open supports Turing (2018) and newer.
gpus() {
    _lspci | awk '
        # lspci -mm -nn: slot "Class [cccc]" "Vendor [vvvv]" "Device [dddd]" ...
        {
            n = split($0, q, "\"")
            class = q[2]; vendor = q[4]; device = q[6]
            if (class !~ /\[03(00|02|80)\]$/) next
            vid = vendor; sub(/.*\[/, "", vid); sub(/\].*/, "", vid)
            name = vendor " " device
            gsub(/ \[[0-9a-f]{4}\]/, "", name)
            if (vid == "8086") v = "intel"
            else if (vid == "1002") v = "amd"
            else if (vid == "10de") v = "nvidia"
            else v = "other"
            gen = "-"
            if (v == "nvidia") gen = (device ~ /(^|[^A-Z])(TU|GA|AD|GH|GB)[0-9][0-9][0-9]/) ? "turing+" : "legacy"
            print v, gen, name
        }'
}

# has_gpu VENDOR [GEN]: true if a GPU from VENDOR (and generation) is present
has_gpu() {
    local vendor="$1" gen="${2:-}"
    gpus | awk -v v="$vendor" -v g="$gen" '$1 == v && (g == "" || $2 == g) {found = 1} END {exit !found}'
}

# suggested_graphics: "open" or "nvidia". Suggest the proprietary driver only
# when an NVIDIA GPU that nvidia-open supports is present.
suggested_graphics() {
    if has_gpu nvidia turing+; then echo nvidia; else echo open; fi
}

# needs_broadcom_wl: true if a Broadcom Wi-Fi card is present
needs_broadcom_wl() {
    _lspci | awk -F'"' '$2 ~ /\[0280\]$/ && $4 ~ /\[14e4\]$/ {found = 1} END {exit !found}'
}

# disks: one line per installable disk: "<path> <size bytes> <transport> <model>"
# Skips read-only devices, the live medium, loop devices and zram.
disks() {
    local json
    if [[ -n "${LSBLK_FILE:-}" ]]; then
        json="$(cat "$LSBLK_FILE")"
    else
        json="$(lsblk -J -d -b -o NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,RO)"
    fi
    local live="${LIVE_DEVICE:-}"
    if [[ -z "$live" && -z "${LSBLK_FILE:-}" ]]; then
        live="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null | sed 's/[0-9]*$//; s/p$//')" || true
    fi
    jq -r --arg live "$live" '
        .blockdevices[]
        | select(.type == "disk")
        | select((.ro | tostring) != "true" and (.ro | tostring) != "1")
        | select(.path != $live)
        | select(.name | test("^(loop|zram|sr)") | not)
        | "\(.path) \(.size) \(.tran // "internal") \((.model // "unknown model") | gsub("\\s+$"; ""))"
    ' <<<"$json"
}

# human_size BYTES: "512 gigabytes" style, for reading aloud
human_size() {
    awk -v b="$1" 'BEGIN {
        split("bytes kilobytes megabytes gigabytes terabytes", u, " ")
        i = 1
        while (b >= 1000 && i < 5) { b /= 1000; i++ }
        printf (b >= 10 || i == 1) ? "%d %s\n" : "%.1f %s\n", b, u[i]
    }'
}

# partition_path DISK N: /dev/sda + 2 -> /dev/sda2, /dev/nvme0n1 + 2 -> /dev/nvme0n1p2
partition_path() {
    local disk="$1" n="$2"
    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p${n}"
    else
        echo "${disk}${n}"
    fi
}

# network_online: true if the Arch mirrors are reachable
network_online() {
    [[ "${BLINUX_OFFLINE:-0}" == 1 ]] && return 1
    [[ "${BLINUX_ONLINE:-0}" == 1 ]] && return 0
    curl -fsS --max-time 8 -o /dev/null https://archlinux.org/ 2>/dev/null
}
