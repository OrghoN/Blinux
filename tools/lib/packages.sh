# shellcheck shell=bash
# Optional stacks and how installer choices map to packages.
#
# Each optional stack is a meta-package in [blinux]; packages/<stack>.txt
# lists what it pulls in. The installer installs the meta-packages, so the
# same stacks can be added later with plain pacman.

STACKS=(aster docs hep ml)

stack_valid() {
    local s
    for s in "${STACKS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
    return 1
}

stack_describe() {
    case "$1" in
        aster) echo "AsTeR spoken math, with Software DECtalk" ;;
        docs) echo "documents: TeX Live, pandoc and braille translation" ;;
        hep) echo "high energy physics: ROOT, Geant4, Pythia and more" ;;
        ml) echo "machine learning: PyTorch, scikit-learn, Jupyter" ;;
    esac
}

# stack_meta_packages GRAPHICS STACK...: meta-packages to install.
# ML with CUDA swaps in blinux-ml-cuda (python-pytorch-cuda). It still installs
# blinux-ml, whose python-pytorch dependency python-pytorch-cuda satisfies.
stack_meta_packages() {
    local graphics="$1" s
    shift
    for s in "$@"; do
        stack_valid "$s" || die "unknown stack: $s"
        if [[ "$s" == ml && "$graphics" == nvidia-cuda ]]; then
            printf '%s\n' python-pytorch-cuda blinux-ml blinux-ml-cuda
        else
            printf 'blinux-%s\n' "$s"
        fi
    done
}

# validate_choices GRAPHICS STACK...: die on combinations that can't work.
validate_choices() {
    local graphics="$1"
    shift
    graphics_valid "$graphics" || die "unknown graphics choice: $graphics (use open, nvidia or nvidia-cuda)"
    local s
    for s in "$@"; do stack_valid "$s" || die "unknown stack: $s (use ${STACKS[*]})"; done
}

# network_packages GRAPHICS STACK...: everything that has to come from the
# network (not in the ISO's offline cache): proprietary drivers and stacks.
network_packages() {
    local graphics="$1"
    shift
    if [[ "$graphics" != open ]]; then
        graphics_packages "$graphics"
    fi
    stack_meta_packages "$graphics" "$@"
}
