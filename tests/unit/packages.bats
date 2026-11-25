#!/usr/bin/env bats
# Installer choices -> packages.

load helpers

setup() { load_libs; }

@test "open source graphics needs nothing from the network" {
    run network_packages open
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "NVIDIA choice installs nvidia-open, not CUDA" {
    run graphics_packages nvidia
    [[ "$output" == *nvidia-open* ]]
    [[ "$output" != *cuda* ]]
}

@test "NVIDIA + CUDA adds cuda and cudnn" {
    run graphics_packages nvidia-cuda
    [[ "$output" == *nvidia-open* ]]
    [[ "$output" == *cuda* ]]
    [[ "$output" == *cudnn* ]]
}

@test "each stack maps to its meta-package" {
    run stack_meta_packages open aster docs hep ml
    [ "$output" = "$(printf 'blinux-aster\nblinux-docs\nblinux-hep\nblinux-ml')" ]
}

@test "ML with CUDA installs blinux-ml-cuda and python-pytorch-cuda" {
    run stack_meta_packages nvidia-cuda ml
    [[ "$output" == *python-pytorch-cuda* ]]
    [[ "$output" == *blinux-ml-cuda* ]]
}

@test "ML without CUDA never pulls CUDA" {
    for g in open nvidia; do
        run network_packages "$g" ml
        [[ "$output" != *cuda* ]]
    done
}

@test "every stack combination with every driver resolves to known lists" {
    local g combo
    for g in open nvidia nvidia-cuda; do
        for combo in "" aster "docs hep" "aster docs hep ml"; do
            # shellcheck disable=SC2086
            run network_packages "$g" $combo
            [ "$status" -eq 0 ]
        done
    done
}

@test "unknown stacks and drivers are rejected" {
    run validate_choices open games
    [ "$status" -ne 0 ]
    run validate_choices cuda
    [ "$status" -ne 0 ]
}

@test "no proprietary package sneaks into the open source driver list" {
    run graphics_packages open
    [[ "$output" != *nvidia* ]]
    [[ "$output" != *cuda* ]]
}
