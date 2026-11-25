#!/usr/bin/env bats
# Hardware detection, driven by recorded lspci/cpuinfo/lsblk output.

load helpers

setup() { load_libs; }

@test "author's machine (Intel Iris Xe) gets open source drivers" {
    LSPCI_FILE="$FIXTURES/hw/lspci-author-intel-irisxe.txt"
    run gpus
    [ "$status" -eq 0 ]
    [[ "$output" == "intel - Intel Corporation Raptor Lake-P [Iris Xe Graphics]" ]]
    [ "$(suggested_graphics)" = open ]
}

@test "NVIDIA Turing card suggests the proprietary driver" {
    LSPCI_FILE="$FIXTURES/hw/lspci-nvidia-turing.txt"
    run gpus
    [[ "$output" == "nvidia turing+ "* ]]
    [ "$(suggested_graphics)" = nvidia ]
}

@test "hybrid Intel + NVIDIA laptop lists both and suggests NVIDIA" {
    LSPCI_FILE="$FIXTURES/hw/lspci-hybrid-intel-nvidia.txt"
    run gpus
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == intel* ]]
    [[ "${lines[1]}" == "nvidia turing+ "*"GA107M"* ]]
    [ "$(suggested_graphics)" = nvidia ]
}

@test "pre-Turing NVIDIA (Pascal) is legacy and stays on open source" {
    LSPCI_FILE="$FIXTURES/hw/lspci-nvidia-pascal.txt"
    run gpus
    [[ "$output" == "nvidia legacy "* ]]
    has_gpu nvidia legacy
    ! has_gpu nvidia turing+
    [ "$(suggested_graphics)" = open ]
}

@test "AMD GPU gets open source drivers" {
    LSPCI_FILE="$FIXTURES/hw/lspci-amd.txt"
    [[ "$(gpus)" == amd* ]]
    [ "$(suggested_graphics)" = open ]
}

@test "Broadcom Wi-Fi is detected, Intel Wi-Fi is not" {
    LSPCI_FILE="$FIXTURES/hw/lspci-broadcom-wifi.txt" needs_broadcom_wl
    ! LSPCI_FILE="$FIXTURES/hw/lspci-author-intel-irisxe.txt" needs_broadcom_wl
}

@test "CPU vendor and microcode package" {
    [ "$(CPUINFO_FILE="$FIXTURES/hw/cpuinfo-intel.txt" cpu_vendor)" = intel ]
    [ "$(CPUINFO_FILE="$FIXTURES/hw/cpuinfo-amd.txt" cpu_vendor)" = amd ]
    [ "$(CPUINFO_FILE="$FIXTURES/hw/cpuinfo-other.txt" cpu_vendor)" = unknown ]
    [ "$(microcode_package intel)" = intel-ucode ]
    [ "$(microcode_package amd)" = amd-ucode ]
    [ -z "$(microcode_package unknown)" ]
}

@test "disk list skips the live medium, loop, zram and DVD drives" {
    LSBLK_FILE="$FIXTURES/hw/lsblk.json" LIVE_DEVICE=/dev/sda run disks
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == "/dev/nvme0n1 1024209543168 nvme WD PC SN810"* ]]
    [[ "${lines[1]}" == "/dev/sdb 500107862016 sata Samsung SSD 870" ]]
}

@test "disk sizes read naturally" {
    [ "$(human_size 1024209543168)" = "1.0 terabytes" ]
    [ "$(human_size 500107862016)" = "500 gigabytes" ]
    [ "$(human_size 31004295168)" = "31 gigabytes" ]
}

@test "partition paths for SATA and NVMe disks" {
    [ "$(partition_path /dev/sda 2)" = /dev/sda2 ]
    [ "$(partition_path /dev/nvme0n1 2)" = /dev/nvme0n1p2 ]
    [ "$(partition_path /dev/vda 1)" = /dev/vda1 ]
}

@test "boot mode follows /sys/firmware/efi" {
    mkdir -p "$BATS_TEST_TMPDIR/efi"
    [ "$(EFI_DIR="$BATS_TEST_TMPDIR/efi" boot_mode)" = uefi ]
    [ "$(EFI_DIR="$BATS_TEST_TMPDIR/missing" boot_mode)" = bios ]
}
