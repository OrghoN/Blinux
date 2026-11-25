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

This README is written to be read with a screen reader: every step is plain text followed by the exact commands, in order. The full design is in [docs/build-plan.md](docs/build-plan.md), and a record of how it was built is in [docs/build-log.md](docs/build-log.md).

## What Blinux is

Blinux talks from the moment it boots, and nothing on the way to a working desktop needs sight:

- **Boot menu:** the speech entry is the default on every boot loader, with a 5 second timeout, so you can just wait.
- **Live system and installer:** espeakup, the speakup console screen reader with the eSpeak NG voice, reads everything. The installer, `blinux-install`, asks one question at a time and reads every option with its number.
- **Desktop:** GNOME on Wayland, with Orca speaking at the login screen and after you log in. X11-only programs still work through XWayland.
- **Audio:** PulseAudio is the sound server. PipeWire runs alongside it only for screen capture and video. `pipewire-pulse` is never installed, so the two never fight over the sound card. Orca speaks through speech-dispatcher, which uses eSpeak NG and PulseAudio.
- **Console speech after install:** off by default, as on the author's machine. One command turns it on, and then espeakup speaks on the text consoles through your PulseAudio.
- **Editor:** Emacs with Emacspeak in `/opt/emacspeak`, using the same eSpeak NG voice. Emacspeak's math server (MathJax with the Speech Rule Engine) reads LaTeX formulas.
- **AsTeR:** spoken math for whole LaTeX documents, in `/opt/emacspeak/aster-math`, speaking with Software DECtalk. It's an optional stack. DECtalk itself is proprietary, so Blinux doesn't distribute it: `blinux-aster-setup` builds it on your own computer if you're entitled to use it.
- **Shell and packages:** zsh with oh-my-zsh and a plain prompt that reads cleanly. yay is ready to use for AUR packages.
- **Dotfiles:** the installer can clone a dotfiles repository and link it into place, the way `OrghoN/.dotfiles` expects.

What gets installed comes in two layers.

- **Base stack:** always installed, and carried on the ISO so it installs without a network. It covers the system, audio and speech, GNOME, zsh, Emacs with Emacspeak, yay and core development tools.
- **Optional stacks:** chosen in the installer, and installable at any time later:
  - `blinux-aster`: AsTeR spoken math (its DECtalk voice is built locally by `blinux-aster-setup`)
  - `blinux-docs`: TeX Live, pandoc and liblouis braille translation
  - `blinux-hep`: ROOT, Geant4, Pythia8, FastJet, HepMC3, LHAPDF and Apptainer. For uproot, awkward and hist, use `uv pip install uproot awkward hist` in each project
  - `blinux-ml`: PyTorch, scikit-learn, pandas, Jupyter
  - `blinux-ml-cuda`: the same with GPU PyTorch
- **Graphics drivers:** an install-time choice. Open source drivers are the default; NVIDIA proprietary, or NVIDIA with CUDA, are downloaded during installation. They're never on the ISO.

## Building the ISO

You need an Arch Linux machine with about 30 gigabytes free, and sudo. Building takes a long time the first time, mostly to compile the AUR packages.

Install the build tools, get the source, build the package repository, then build the ISO:

```sh
sudo pacman -S --needed archiso devtools arch-install-scripts git rsync
git clone https://github.com/OrghoN/Blinux.git
cd Blinux
make repo
make iso
```

`make repo` runs `scripts/build-repo.sh`, which builds every Blinux package in a clean chroot and writes them to `repo/x86_64`. `make iso` runs `scripts/build-iso.sh`, which writes the ISO and its checksums to `out/`.

Released ISOs come with a signature. To check a downloaded one:

```sh
gpg --verify blinux-*.iso.sig
sha256sum -c sha256sums
```

## Writing the USB stick

First find the USB stick's device name. `lsblk` lists the disks with their sizes; the stick is usually the one with a size matching it, often `/dev/sdb`. Everything on the device you name is erased, so check twice.

```sh
lsblk -d -o NAME,SIZE,MODEL,TRAN
sudo dd if=out/blinux-YYYY.MM.DD-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `YYYY.MM.DD` with the date in your ISO's file name, and `sdX` with the stick's name.

## Booting and installing

Boot from the stick and wait. After a short beep, the boot menu starts the speech entry on its own after 5 seconds, and once the system is up you hear a welcome message.

For Wi-Fi, connect first with `iwctl`. Ethernet connects by itself. Without any network, the base system still installs from the stick, and drivers and optional stacks can be added later.

Start the installer:

```sh
blinux-install
```

It asks these questions, one at a time:

1. Which disk to install on. Each disk is read out with its size, model and connection. You then type the word erase twice to confirm.
2. Whether to encrypt the disk, and if so, a passphrase, typed twice.
3. Whether to turn on speech on the text consoles too.
4. Your user name, then your password, typed twice.
5. The computer's name and your time zone, for example America/Toronto.
6. Whether to install microcode updates for your processor.
7. Graphics drivers: open source, NVIDIA proprietary, or NVIDIA with CUDA. The installer reads out the graphics cards it found and suggests one.
8. The optional stacks, one yes or no question each: AsTeR, documents, high energy physics, machine learning.
9. Whether to set up dotfiles from a git repository. The default is `https://github.com/OrghoN/.dotfiles`.

Then it reads back a summary, and nothing changes until you type install. While it works it says which of the 11 steps it is on, and says "Still working" every minute during long downloads. The detailed log is in `/var/log/blinux-install.log`. When it's done, remove the stick and reboot.

To practise or to install unattended, answers can be saved to a file and replayed:

```sh
blinux-install --save-config answers.json
blinux-install --dry-run --config answers.json
blinux-install --config answers.json
```

## After the first boot

Orca speaks at the login screen. After logging in, these commands add the things you didn't choose during installation:

```sh
sudo blinux-console-speech enable
sudo blinux-drivers
sudo pacman -S blinux-hep blinux-ml
sudo pacman -S blinux-aster blinux-docs
blinux-aster-setup
blinux-dotfiles --url https://github.com/OrghoN/.dotfiles
```

- `blinux-console-speech enable` turns on espeakup on the text consoles. `disable` turns it off and `status` tells you which it is.
- `blinux-aster-setup` builds AsTeR's DECtalk voice on your computer, after explaining DECtalk's licence and asking first.
- `blinux-drivers` switches between open source, NVIDIA and NVIDIA with CUDA graphics, without reinstalling.
- `blinux-dotfiles` clones the repository into `~/.dotfiles` and links it into place, moving any file it replaces aside as `NAME.blinux-backup`.
- yay works straight away, for example `yay -S some-aur-package`.

## Using Emacspeak and AsTeR

Emacspeak starts with Emacs for every user. If your own `init.el` already loads `emacspeak-setup.el`, as `OrghoN/.dotfiles` does, it isn't loaded twice. To start Emacs without Emacspeak, set `BLINUX_NO_EMACSPEAK=1`.

To use AsTeR, install the `blinux-aster` stack, then give it its voice. Software DECtalk is proprietary: its licence allows use and copying only with a licence from Fonix, so Blinux never builds or distributes it. If you're entitled to use it, this builds DECtalk and Emacspeak's DECtalk server on your own computer, following Raman's notes:

```sh
sudo pacman -S blinux-aster
blinux-aster-setup
```

Then in Emacs run `M-x load-library RET aster` followed by `M-x aster`. Its commands are on the `C-; SPC` and `C-' a` prefixes, and `M-x describe-function RET aster` shows its help.

### Building Emacspeak and AsTeR by hand

On a system that isn't Blinux, these are Raman's steps, which the Blinux packages follow. Emacspeak, from the [manual](https://tvraman.github.io/emacspeak/manual/Quick-Installation.html):

```sh
git clone https://github.com/tvraman/emacspeak
cd emacspeak
make config
make
cd servers/native-espeak
make
export DTK_PROGRAM=espeak
```

Then add `(load-file "<emacspeak-dir>/lisp/emacspeak-setup.el")` at the top of your Emacs init file. For spoken math, run `npm install` in `emacspeak/js/node`.

AsTeR, from the [blog post](https://emacspeak.blogspot.com/2022) of 21 December 2022. It needs Emacspeak 57 or later, slime and auctex in Emacs, flex, SBCL, and [Software DECtalk](https://github.com/dectalk/dectalk):

```sh
cd emacspeak
git clone https://github.com/tvraman/aster-math
cd aster-math/lisp
make
```

Then add `aster-math/ui/` to your Emacs `load-path`. With GCC 15 or newer, build AsTeR's lexer with `make -C lexer CFLAGS="-O2 -std=gnu17"`, because its C predates the C23 default.

## Running the tests

Tests come in six layers, and every one runs with the same command locally and in CI:

```sh
make lint
make unit
make packages
make test-iso
make test-a11y
make ci
```

- `make lint`: static checks. It checks the package lists, including that `pipewire-pulse` never appears and that NVIDIA and CUDA never land in the base stack. It also checks the configs, that every boot loader defaults to speech, and that the commands in this README are real.
- `make unit`: about 70 bats tests of the installer and helpers, run without touching the system. Hardware detection is checked against recorded output from real machines.
- `make packages`: builds the package repository, checks that every combination of drivers and stacks resolves, and installs each package into a fresh chroot to check that it works. Needs sudo.
- `make test-iso`: boots the ISO in QEMU with KVM, records what it says, checks it with offline speech-to-text, and installs and boots every test case. Choose cases with `CASES="minimal encrypted"` and firmware with `FIRMWARE=uefi`.
- `make test-a11y`: checks Orca, AT-SPI and Emacspeak inside the installed desktop.
- `make ci`: what every pull request runs, lint and unit.

When a QEMU test fails, its serial log, recorded audio and screenshots are in `tests/integration/artifacts/`, and CI keeps the same files as a downloadable artifact. Before each release, the manual checklist in `tests/manual/release-checklist.md` is worked through with the screen off.

## Releases and package repositories

- **Releases:** pushing a version tag builds and signs everything, tests the exact ISO, and creates a draft release. The draft is published once the manual checklist passes.
- **Stable repository:** `[blinux]` is served from GitHub Releases. Installed systems already have it in `/etc/pacman.d/blinux.conf`.
- **Testing repository:** every change to `main` is published to `[blinux-testing]`. To try it, add this to `/etc/pacman.conf`:

```sh
sudo tee -a /etc/pacman.conf <<'EOF'

[blinux-testing]
Server = https://github.com/OrghoN/Blinux/releases/download/repo-testing
EOF
sudo pacman -Syu
```

## Troubleshooting audio

If something stops talking, these show what each part of the audio stack is doing:

```sh
pactl info
systemctl --user status pulseaudio speech-dispatcher
systemctl status espeakup
blinux-console-speech status
alsamixer
```

- `pactl info` should say `Server Name: pulseaudio`. If it names PipeWire, `pipewire-pulse` has been installed; remove it with `sudo pacman -R pipewire-pulse`, then log out and back in.
- PipeWire running is normal: it handles screen capture and video only.
- In `alsamixer`, M unmutes the selected channel and the arrow keys change the volume. `sudo alsactl store` keeps the setting.
- If Orca is silent, Super+Alt+S turns it off and on again.
- On laptops with Intel audio, `sof-firmware` must be installed; Blinux installs it in the base stack.
