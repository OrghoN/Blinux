# Blinux

Linux distribution designed for the blind or visually impaired.
It uses orca as the main screen reader in a gnome environment running on wayland, with xwayland providing x11 emulation for apps that still need it.
It is based on arch linux and uses the auditory interface that the arch iso provides for installation using espeakup.
Audio uses PulseAudio as the sound server, with PipeWire alongside it for screen capture and video, the same way they coexist on my machine, so espeakup, orca (through speech-dispatcher) and emacspeak can all speak.
Emacspeak is also installed with emacs for coding and aster is also installed for reading mathematics and other technical documents.
Both are built from source following the instructions on T.V. Raman's [Emacspeak manual](https://tvraman.github.io/emacspeak/manual/Quick-Installation.html) and [blog](https://emacspeak.blogspot.com/2022).
zsh is the default shell and is managed by oh-my-zsh.
The yay AUR helper is set up from the get go so AUR packages can be installed right after installation.
It is designed to be used with the `OrghoN/.dotfiles` repository in github.
It should also come equipped with standard development tools for high energy physics and machine learning.
The packages on my computer are being used to get a first list of potentially useful packages together.

## Base and optional stacks

The base stack is always installed and is carried on the ISO so it can be installed offline: the system, audio and speech, gnome, zsh, emacs with emacspeak, yay and core development tools.
Optional stacks are chosen during installation and can also be installed later: aster (spoken math), documents (texlive, pandoc), high energy physics and machine learning.
Proprietary NVIDIA drivers and CUDA are never on the ISO; they are an install-time choice, and can be added later too.

## Setup

Blinux is still being built, so there are no setup commands yet.
As the build scripts and installer are written, this README will be updated with an explanation and the exact sequence of commands to run: building the ISO, writing it to a USB stick, booting and installing, and post-install steps.
See [docs/build-plan.md](docs/build-plan.md) for the full plan.
