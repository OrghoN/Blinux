# Blinux Build Plan

## Summary

Blinux is an Arch Linux–based distribution for blind and visually impaired users. It ships as a bootable ISO that talks from the first second: the live environment uses `espeakup` (the speakup console screen reader driven by eSpeak NG), just like the official Arch ISO's accessible boot entry. The installed system boots into a **GNOME Wayland** session (with **XWayland** for X11 apps) and uses **Orca** as the screen reader, uses **zsh + oh-my-zsh** as the default shell, and comes with **Emacs + Emacspeak** for coding and **Aster** for listening to math and technical documents. The **`yay` AUR helper** is installed and ready to use from first boot. It's also set up to work with the `OrghoN/.dotfiles` repository, and it ships development stacks for **high energy physics (HEP)** and **machine learning (ML)**.

The audio stack copies the author's working machine: **PulseAudio** is the sound server, and **PipeWire** runs alongside it only for screen capture and video. Speech from espeakup, speech-dispatcher and Emacspeak all goes through PulseAudio. The build uses **archiso** with a custom profile. An installer that speaks at every step (a script wrapped around `archinstall`, or written by hand) deploys a package set taken from the author's current machine (203 explicitly installed packages as of 2026-11-25, including `orca`, `espeakup`, `emacs`, `root`, `zsh` and the full GNOME suite).

### Milestones at a glance

| # | Milestone | Outcome |
|---|-----------|---------|
| 0 | Repo scaffolding | archiso profile skeleton, package lists, CI build, `yay` packaged in `[blinux]` |
| 1 | Talking live ISO | Boots with espeakup speech by default; can install vanilla Arch |
| 2 | Accessible desktop | Installed system auto-starts GNOME (Wayland) + Orca at GDM and in the session; audio servers coexist without fighting over the device |
| 3 | Shell and editor | zsh/oh-my-zsh default; Emacs + Emacspeak working with speech server |
| 4 | Technical reading | AsTeR (aster-math + Software DECtalk) reading LaTeX math; SRE math in Emacspeak by default |
| 5 | Dotfiles integration | Installer optionally clones and applies `OrghoN/.dotfiles` |
| 6 | Optional stacks + drivers | `blinux-hep`, `blinux-ml`, `blinux-ml-cuda`, `blinux-aster`, `blinux-docs`; NVIDIA/CUDA as an install-time choice |
| 7 | Release | Signed ISO, checksums, README with explanation + full command sequence, accessibility test pass |

---

## Conceptual Take

### Design principles

1. **Speech from power-on to desktop.** At no point should a user need sighted help: not in the bootloader, the live shell, the installer, the first boot, the login screen or the desktop. Every transition between these is where accessible systems usually break, so each one is a first-class test case.
2. **One voice where possible.** espeakup (console), Orca (GUI) and Emacspeak (Emacs) are three separate screen readers. Use the same synthesizer (eSpeak NG via speech-dispatcher) and the same default rate and voice, so the experience feels continuous.
3. **Stay close to upstream Arch.** Blinux should be "Arch plus an accessible, opinionated default." Use official repos where possible, keep a small custom repo only for AUR-only packages (Emacspeak, some HEP tools), and avoid forking core components. That keeps maintenance manageable for one person.
4. **Keyboard-first, terminal-friendly.** Users who rely on a screen reader tend to live in the terminal and in Emacs. GNOME stays the GUI fallback for browsers, office documents and similar apps, but the shell and editor experience is the core product.
5. **Reproducible and declarative.** Keep the package lists, configs and dotfiles hook in git, and make the ISO build deterministic in CI.

### Who it's for

- Blind or low-vision developers and scientists, specifically ones doing physics and ML work, who want a ready-made Arch setup without building the accessibility stack by hand.
- First and foremost, the author's own workstation (hence the dotfiles and the package list from the current machine). Generalize later.

### What it's not, at least at first

- A new desktop environment or a new screen reader.
- A general-purpose beginner distro. It targets technical users.
- A distro with its own mirror and package infrastructure. Use Arch's, plus one small extra repo.

### Risks and open questions

- **Emacspeak and AsTeR are built from source** (Raman's instructions), so their PKGBUILDs have to track upstream. AsTeR also depends on Software DECtalk, which has to be built and packaged too.
- **Audio contention.** espeakup (a root system service), speech-dispatcher, PulseAudio and PipeWire all touch the sound card. The author's machine runs them side by side. Blinux reproduces that exact setup (see "Audio and speech") instead of inventing a new one, but the GDM-to-session and TTY-to-desktop hand-offs still need testing on every release.
- **Wayland gaps.** Blinux is Wayland-only: GNOME on Wayland, with XWayland for X11 apps, and no Xorg session. Orca on Wayland still has a few gaps (some global keyboard grabs and apps that are only half Wayland-native). Track them in Orca's issue tracker instead of shipping an X11 fallback.
- **CUDA and proprietary drivers** can't be shipped freely in every configuration, so they're an install-time choice and never on the ISO (see "Hardware drivers and CUDA").
- **ISO size.** The ISO only carries the base stack. ROOT, Geant4 data, PyTorch, CUDA, TeX Live and AsTeR's toolchain are optional stacks installed from the network (see "Base and optional stacks").

---

## Technical Details

### 1. Repository layout

```
blinux/
├── README.md
├── docs/
│   └── build-plan.md          # this file
├── profile/                   # archiso profile (copied from /usr/share/archiso/configs/releng)
│   ├── profiledef.sh
│   ├── packages.x86_64        # live ISO packages
│   ├── pacman.conf            # + [blinux] custom repo
│   ├── airootfs/              # files overlaid onto the live system
│   │   ├── etc/systemd/system/espeakup.service.d/
│   │   ├── etc/pulse/default.pa.d/   # live ISO audio config
│   │   ├── root/.zshrc
│   │   └── usr/local/bin/blinux-install
│   ├── grub/ syslinux/ efiboot/   # boot menus with accessible entries as default
├── packages/
│   ├── base.txt               # blinux-base: system, audio, speech, GNOME, shell, editor, core dev
│   ├── drivers-nvidia.txt     # install-time choice
│   ├── cuda.txt               # install-time choice
│   ├── aster.txt              # optional stacks ↓
│   ├── docs.txt
│   ├── hep.txt
│   ├── ml.txt
│   └── aur.txt                # tclx, slime, oh-my-zsh-git, ...
├── pkgbuilds/                 # PKGBUILDs for the [blinux] repo
│   ├── yay/                   # AUR helper, prebuilt so it's there from first boot
│   ├── emacspeak/
│   ├── aster-math/            # AsTeR, per Raman's 2022 blog post
│   ├── dectalk/               # Software DECtalk, needed by AsTeR
│   ├── blinux-config/         # config package (see the `blinux-config` section)
│   └── blinux-meta/           # blinux-base, blinux-hep, blinux-ml, blinux-ml-cuda, blinux-aster, blinux-docs
├── installer/                 # talking install script
├── scripts/
│   ├── harvest-packages.sh    # derive lists from the author's machine
│   ├── build-repo.sh
│   └── build-iso.sh
└── .github/workflows/build.yml
```

### 2. Seeding the package list from the current machine

The author's machine currently has 203 explicitly installed packages. Pull them out and sort them into categories:

```sh
pacman -Qqen > packages/raw-native.txt     # from official repos
pacman -Qqem > packages/raw-foreign.txt    # AUR / local
```

Then sort by hand into the `packages/*.txt` files. Drop anything hardware- or machine-specific: microcode, GPU drivers, laptop tools, personal apps. Hardware-specific packages become installer questions (e.g. `intel-ucode` vs `amd-ucode`, open source vs NVIDIA drivers). A `harvest-packages.sh` script can diff the machine against the current lists over time so new useful packages get flagged.

### 3. Base and optional stacks

Everything installs in two layers. Each layer is a meta-package in `[blinux]`, so the same groups that the installer offers can also be added or removed later with `pacman`/`yay`.

**Base stack (`blinux-base`): always installed, and carried on the ISO as an offline package cache so a base install works without network.**

| Area | Packages |
|------|----------|
| System | `base`, `linux`, `linux-firmware`, `sof-firmware`, microcode (`intel-ucode`/`amd-ucode`, chosen by the installer), `networkmanager`, `sudo` |
| Build / AUR | `base-devel`, `git`, `yay` |
| Audio | `pulseaudio`, `pulseaudio-alsa`, `pulseaudio-bluetooth`, `pipewire`, `pipewire-media-session`, `alsa-utils`, `alsa-ucm-conf` |
| Speech and braille | `espeak-ng`, `speech-dispatcher`, `espeakup`, `orca`, `brltty` |
| Desktop | `gnome`, `gdm`, `xorg-xwayland`, `mesa` |
| Shell | `zsh`, oh-my-zsh |
| Editor | `emacs`, `emacspeak`, `speech-rule-engine` (SRE math) |
| Core dev | `gcc`, `clang`, `cmake`, `ninja`, `gdb`, `python`, `python-pip`, `uv` |
| Config | `blinux-config` |

**Optional stacks: picked in the installer (none are selected by default), installed from the network, and installable later.**

| Meta-package | Contents | Install later with |
|--------------|----------|--------------------|
| `blinux-aster` | `aster-math`, `dectalk`, `sbcl`, `flex`, `cl-asdf`, `slime`, `auctex` | `sudo pacman -S blinux-aster` |
| `blinux-docs` | `texlive`, `pandoc`, `liblouis` | `sudo pacman -S blinux-docs` |
| `blinux-hep` | ROOT, Geant4, Pythia8, FastJet, … (see "HEP and ML stacks") | `sudo pacman -S blinux-hep` |
| `blinux-ml` | Python scientific stack, PyTorch (CPU), JAX, Jupyter | `sudo pacman -S blinux-ml` |
| `blinux-ml-cuda` | `cuda`, `cudnn`, `python-pytorch-cuda` (needs NVIDIA drivers; see "Hardware drivers and CUDA") | `sudo pacman -S blinux-ml-cuda` |

Proprietary bits (NVIDIA drivers, CUDA) are **never in the base stack or on the ISO**. They're always an install-time choice, which keeps the ISO freely redistributable and small enough to download.

### 4. Live ISO (archiso)

- Start from `releng`: `cp -r /usr/share/archiso/configs/releng profile/`.
- The Arch ISO already ships `espeakup` and has an accessible boot entry ("Arch Linux install medium with speech"). In Blinux, **make the speech entry the default** and give the menu a short timeout, so a blind user just waits and gets speech.
- Add to `packages.x86_64`: `espeakup`, `espeak-ng`, `alsa-utils`, `brltty` (braille displays), `archinstall`, `zsh`, `git`, `base-devel`, `yay` (from `[blinux]`).
- Set the default shell in the live environment to zsh with a minimal, screen-reader-friendly prompt (no Unicode glyphs or right-side prompts, which screen readers read badly).
- A welcome message, read aloud on login, explains how to start the installer: `blinux-install`.
- Build: `mkarchiso -v -w /tmp/archiso-work -o out/ profile/`.

### 5. Audio and speech

Several audio systems coexist on the author's machine (checked 2026-11-25). Blinux copies that setup as-is:

| Component | Role on the author's machine | Blinux default |
|-----------|------------------------------|----------------|
| `pulseaudio` (+ `pulseaudio-alsa`, `pulseaudio-bluetooth`) | **The** sound server (`pactl info` → `Server Name: pulseaudio`), per-user, socket-activated | Same. Owns the sound card in every graphical session |
| `pipewire` + `pipewire-media-session` | Running, but only for screen capture and camera/video (GNOME screencast, portals). No audio role | Same. **Don't** install `pipewire-pulse` or `wireplumber`: `pipewire-pulse` conflicts with `pulseaudio`, and two audio servers would fight over the device |
| `jack2` | Installed for pro-audio apps; not running | Optional, pulled in by apps that need it |
| `alsa-lib`, `alsa-plugins`, `alsa-ucm-conf` | ALSA's default device is routed into PulseAudio by `pulseaudio-alsa` | Same |
| `sof-firmware` | Needed by this machine's audio chip (`skl_hda_dsp_generic`, Intel SOF) | Always installed. Without it, many modern Intel laptops have **no sound at all**, so no speech |
| `speech-dispatcher` | Active user service; Orca talks through it | Same; its output module is `pulse` |
| `espeak-ng` | Synthesizer for everything | Same |
| `espeakup` | Installed, **disabled** | Live ISO: enabled. Installed system: opt-in (see below) |

How each speech path reaches the speakers:

- **Orca → speech-dispatcher → espeak-ng → PulseAudio** (user session). Set `AudioOutputMethod "pulse"` in `/etc/speech-dispatcher/speechd.conf`.
- **Emacspeak → espeak server (`servers/native-espeak`) → libespeak-ng → PulseAudio** (user session; espeak-ng's pcaudiolib tries Pulse first).
- **espeakup → ALSA.** This is the hard one: espeakup runs as root, before and outside any user's PulseAudio.
  - *Live ISO:* no PulseAudio runs, so espeakup gets ALSA to itself. This is the stock Arch ISO behaviour and works as-is.
  - *Installed system:* matches the author's machine, so espeakup is **off by default** and Orca handles speech once GDM is up. Opt-in console speech is provided by `blinux-console-speech enable`, which:
    1. Adds a PulseAudio drop-in (`/etc/pulse/default.pa.d/10-blinux-espeakup.pa`) that loads `module-native-protocol-unix auth-anonymous=1 socket=/tmp/blinux-pulse.sock`, so root's espeakup can play through the logged-in user's server.
    2. Adds an `espeakup.service.d/pulse.conf` drop-in with `Environment=PULSE_SERVER=unix:/tmp/blinux-pulse.sock`, so speech goes through PulseAudio instead of opening the hardware directly.
    3. Enables `espeakup.service`.

    With no one logged in, espeakup falls back to plain ALSA. *This is a design to try out, not something already shown to work: confirm it on real hardware before making it the default.*
- **GDM greeter:** GDM's own user session starts its own PulseAudio. Orca at the greeter speaks through that one. On login, logind switches the seat and the user's PulseAudio takes over the device. Test this hand-off explicitly.

`blinux-config` ships these configs. The installer runs `alsactl store` after unmuting and setting the default volume, so the first boot is never silent.

### 6. Display: Wayland with XWayland

- GNOME runs on Wayland only. GDM keeps `WaylandEnable=true` (the default). Ship no Xorg session and don't install `xorg-server`.
- `xorg-xwayland` is always installed (it's on the author's machine too) so X11-only apps keep working inside the Wayland session, e.g. ROOT's X11 GUI (`TBrowser`, canvases), older Java/Tk apps and some HEP event displays. AT-SPI works for X11 apps under XWayland too, so Orca can still read them.
- Set `QT_QPA_PLATFORM=wayland;xcb` and `MOZ_ENABLE_WAYLAND=1` (already the default in current Firefox) in `/etc/environment.d/` so toolkits use Wayland first and fall back to X11.
- With NVIDIA proprietary drivers (see "Hardware drivers and CUDA"), `nvidia_drm.modeset=1` must be set. Otherwise GDM's udev rule quietly disables Wayland and the user lands in a session Blinux doesn't support.

### 7. Hardware drivers and CUDA

Graphics drivers are chosen **at install time**. The installer detects the GPU (`lspci -d ::03xx`), reads it aloud, and suggests a default. The user can override it.

| Choice | Packages | When |
|--------|----------|------|
| 1. Open source (default) | `mesa`, `vulkan-intel` / `vulkan-radeon`, `intel-media-driver` / `libva-mesa-driver` | Intel, AMD, or NVIDIA with `nouveau`. (The author's machine has Intel Iris Xe.) |
| 2. NVIDIA proprietary | `nvidia-open` (Turing and newer) or `nvidia` (older), `nvidia-utils`, `nvidia-settings`, optional `lib32-nvidia-utils` | NVIDIA GPU detected |
| 3. NVIDIA proprietary + CUDA | choice 2 + `cuda`, `cudnn`; if `blinux-ml` is also chosen, it swaps `python-pytorch` for `python-pytorch-cuda` (i.e. installs `blinux-ml-cuda`) | NVIDIA GPU and GPU compute wanted |

For choices 2 and 3, the installer also:
- adds `nvidia_drm.modeset=1` to the kernel command line so GNOME stays on Wayland (see "Display"),
- adds the `nvidia` modules to `mkinitcpio.conf` and rebuilds the initramfs,
- installs a pacman hook so that kernel updates rebuild the initramfs.

Other non-free firmware (e.g. `broadcom-wl` for some Wi-Fi cards) is handled the same way: detect it, explain it, ask. To switch drivers after install, run `blinux-drivers` (a small helper using the same logic), so nobody has to reinstall to add CUDA.

### 8. `blinux-config` meta package

Put all system configuration in one package instead of scattering it across the installer. That way, installed systems pick up config updates through `pacman -Syu` (or `yay`).

It depends on the accessibility and desktop package lists and installs:

- `/etc/dconf/db/gdm.d/00-blinux`: enables `org.gnome.desktop.a11y.applications screen-reader-enabled=true` for the GDM greeter, so Orca speaks at login.
- `/etc/dconf/db/local.d/00-blinux`: the same for user sessions, plus sensible defaults (disable animations, larger cursor, high-contrast toggle bound).
- `/etc/speech-dispatcher/speechd.conf` overrides: default module `espeak-ng`, output method `pulse`, a shared rate and voice.
- `/etc/xdg/autostart/` entries only where dconf can't do the job.
- The audio configs from "Audio and speech": the PulseAudio drop-in, the `espeakup` drop-in, `/etc/environment.d/` Wayland variables, and the `blinux-console-speech` helper. espeakup stays disabled unless the user opts in.
- `/etc/skel/.zshrc` with oh-my-zsh and an accessible theme (no powerline glyphs).
- `/etc/skel/.emacs.d/` or a site-start file that loads Emacspeak.
- The default shell for new users is set by the installer (`useradd -s /usr/bin/zsh`).

### 9. Installer

**Option A (recommended to start):** a `blinux-install` shell script that wraps `archinstall` with a JSON config (`--config blinux.json`). Use `archinstall`'s menu-free mode, with the script asking the few required questions through plain line-by-line `read` prompts. These work well with espeakup; curses menus don't.

Questions to ask:
1. Target disk (list with size and model, read aloud, confirm twice).
2. Encryption yes/no, and the passphrase.
3. Console speech on the installed system (espeakup through PulseAudio)? Default no, matching the author's machine.
4. Username, password and hostname.
5. CPU microcode (detected automatically, then confirmed).
6. Graphics driver: open source / NVIDIA proprietary / NVIDIA proprietary + CUDA (see "Hardware drivers and CUDA").
7. Optional stacks, one yes/no question each: AsTeR, documents, HEP, ML (choosing ML together with CUDA installs `blinux-ml-cuda`).
8. Clone `OrghoN/.dotfiles`? (y/n, plus a custom URL.)

Then: partition → pacstrap `blinux-base` from the ISO's offline cache → install the chosen drivers and optional stacks from the network (skipped with a spoken warning if offline; they can be installed later) → bootloader (systemd-boot or GRUB) → enable `gdm`, `NetworkManager`, `bluetooth` (and `espeakup` only if the user asked for console speech) → copy the audio mixer state (`alsactl store`) so volume isn't muted on first boot → speak "Installation complete, remove the media and press Enter to reboot."

**Option B (later):** a custom Python installer built on the `archinstall` library, for better error handling and progress that's spoken aloud.

### 10. Shell: zsh and oh-my-zsh

- Install `zsh`, and `oh-my-zsh-git` from the AUR (repackaged in `[blinux]`) or vendor it into `/usr/share/oh-my-zsh`.
- Theme: a plain-ASCII prompt. Avoid `agnoster`, `powerlevel10k` and right prompts (RPROMPT), which clutter speech output.
- Useful plugins: `git`, `sudo`, `history-substring-search`, `zsh-autosuggestions` (consider disabling it by default, since inline suggestions can be noisy with speakup).

### 11. AUR helper: yay

`yay` is part of the system from the start, so the user never has to bootstrap it by hand. Bootstrapping means cloning, `makepkg` and reading build output by ear, which is the kind of fiddly first-boot task Blinux exists to remove.

- **How it ships:** build `yay` (or `yay-bin`) from its AUR PKGBUILD in a clean chroot and publish it in the `[blinux]` repo (see "Custom repository"). It then installs with plain `pacman`, on the live ISO and through `pacstrap` on the target, and doesn't need to be compiled during install. Bump it with the monthly CI rebuild.
- **Dependencies:** `base-devel` and `git` are always installed, because yay needs them to build anything from the AUR.
- **Default config:** `blinux-config` ships `/etc/skel/.config/yay/config.json` with output that reads better through a screen reader, e.g. `"diffmenu": false`, `"editmenu": false`, `"cleanAfter": true`, `"answerclean": "None"` and `"removemake": "yes"`. This cuts down interactive menus. The user can still review PKGBUILDs with `yay -G` or `yay --editmenu`.
- **Sudo:** the installer adds the user to `wheel` and enables `%wheel ALL=(ALL:ALL) ALL` in `/etc/sudoers.d/10-wheel`, so yay can call `pacman`.
- **Post-install stacks:** the HEP/ML bundles that need AUR packages (e.g. `geant4`, `delphes`) can be installed after setup with `yay -S blinux-hep`. They also come prebuilt in `[blinux]`, so yay mostly handles the user's own extras.
- **Test:** after install, run `yay -S --noconfirm` on a small AUR package as the new user in the QEMU test.

### 12. Emacs, Emacspeak and AsTeR

Both are built from source, following T.V. Raman's own instructions: the [Emacspeak manual's Quick Installation](https://tvraman.github.io/emacspeak/manual/Quick-Installation.html) and the [Emacspeak blog post "AsTeR: Spoken Math On The Emacspeak Audio Desktop" (2022-12-21)](https://emacspeak.blogspot.com/2022). The PKGBUILDs in `pkgbuilds/` script exactly these steps, so `[blinux]` ships prebuilt packages. The same steps are documented in the README for anyone building by hand.

**Emacspeak** (`pkgbuilds/emacspeak/`, tracks the latest tag of `github.com/tvraman/emacspeak`):

```sh
git clone https://github.com/tvraman/emacspeak
cd emacspeak
make config
make
cd servers/native-espeak     # needs espeak-ng installed first
make
```

- Install to `/usr/share/emacs/site-lisp/emacspeak/`.
- `/etc/profile.d/emacspeak.sh` sets `export DTK_PROGRAM=espeak`, so Emacspeak uses the same eSpeak NG voice as Orca and espeakup.
- Load it from a site-start file: `(load-file "/usr/share/emacs/site-lisp/emacspeak/lisp/emacspeak-setup.el")`. A `BLINUX_NO_EMACSPEAK=1` environment variable skips loading it.
- Build deps: `emacs`, `espeak-ng`, `tcl` and `tclx` (the speech servers are Tcl scripts. Check `tclx` against the current server code, since it may be AUR-only).

**AsTeR (aster-math)**: spoken math for LaTeX documents. Ships as an optional stack (see "Base and optional stacks"), because it pulls in a Lisp toolchain and a second synthesizer. The steps from Raman's post:

1. **Prerequisites**
   - Emacspeak **57.0 or later** (from GitHub, as above).
   - `slime` and `auctex` in Emacs (Raman uses `M-x package-install`. Blinux installs them system-wide from Arch/AUR packages instead, so it works offline).
   - `flex`, `sbcl` and `cl-asdf` from the package manager.
   - **Software DECtalk** from `github.com/dectalk/dectalk`, built and installed, plus Emacspeak's `dtk-soft` server for it. AsTeR uses DECtalk for its voice and audio formatting, not eSpeak.
2. **Build**, inside the Emacspeak directory:

   ```sh
   cd <emacspeak-dir>
   git clone https://github.com/tvraman/aster-math
   cd aster-math/lisp && make
   ```

3. **Use**: add `aster-math/ui/` to the Emacs `load-path` (the Blinux site-start file does this when the package is installed), then `M-x load-library RET aster`, `M-x aster`. Commands are on the `C-; SPC` and `C-' a` prefixes. `M-x describe-function RET aster` shows help.

Packaging: `pkgbuilds/dectalk/` (Software DECtalk) and `pkgbuilds/aster-math/` (depends on `emacspeak>=57`, `dectalk`, `sbcl`, `flex`, `cl-asdf`, `slime`, `auctex`). AsTeR breaks the "one voice" principle on purpose. While reading math the user hears DECtalk, which is fine since that's the voice the rendering is designed for. For lighter math reading without AsTeR, Emacspeak's built-in Speech Rule Engine (SRE) math support ("poor man's AsTeR", per Raman) works with the default eSpeak voice. To enable it, package the `speech-rule-engine` Node module in the base stack.

- Also in the documents stack: `texlive`, `pandoc`, `liblouis` (braille translation) and `brltty`.

### 13. Dotfiles integration

- The installer clones `https://github.com/OrghoN/.dotfiles` into `~/.dotfiles` as the new user and runs its bootstrap (stow, chezmoi, a script, whatever the repo uses).
- Blinux defaults should live in `/etc/skel` and `/etc` (system level), so user dotfiles override them cleanly without conflicts.
- Coordinate: anything accessibility-critical (Orca enabled, speech-dispatcher config) stays system-level, so a broken dotfile can't make the machine silent.

### 14. HEP and ML stacks

**HEP (`packages/hep.txt`)**
- `root` (already on the author's machine), `geant4` + datasets (AUR, large), `hepmc3`, `pythia8`, `fastjet`, `lhapdf`, `delphes` (AUR), `python-uproot`, `python-awkward`, `python-hist`, `python-scikit-hep` bits.
- `gcc`, `clang`, `cmake`, `ninja`, `gfortran`, `boost`, `eigen`, `gsl`.

**ML (`packages/ml.txt`)**
- `python`, `python-pip`, `python-numpy`, `python-scipy`, `python-pandas`, `python-scikit-learn`, `python-matplotlib`, `jupyterlab` (note: Jupyter's web UI has mixed screen-reader support. Also provide `emacs-jupyter` / `ein` and plain `ipython`).
- `python-pytorch` (CPU) and `python-jax` in `blinux-ml`. `cuda`, `cudnn` and `python-pytorch-cuda` are only in `blinux-ml-cuda`, which is installed only when the NVIDIA + CUDA driver choice is made.
- `uv` or `python-poetry` for per-project environments, `conda`/`micromamba` optional for HEP compatibility.

**Accessible plotting:** matplotlib output is visual. Include tools that make data readable without sight, e.g. `python-sonification` libraries (`astronify`, `sonify`), and make sure tabular summaries and `rich`/plain-text output are easy to get.

These are the optional `blinux-hep`, `blinux-ml` and `blinux-ml-cuda` meta-packages from "Base and optional stacks". The installer offers them, and they can be installed at any time afterwards.

### 15. Custom repository `[blinux]`

- Build AUR and custom PKGBUILDs in a clean chroot (`extra-x86_64-build` from `devtools`).
- Sign packages with a dedicated GPG key, and generate the db with `repo-add -s blinux.db.tar.zst *.pkg.tar.zst`.
- Host it on GitHub Releases or Pages and add it to `pacman.conf`, for both the ISO and installed systems.

### 16. CI and builds

- A GitHub Actions workflow running in an `archlinux:latest` container (needs `--privileged` for mkarchiso):
  1. Build the `[blinux]` repo packages.
  2. Run `mkarchiso`.
  3. Upload the ISO + `sha256sums` + signature as an artifact or release.
- Monthly scheduled rebuild to track Arch updates.

### 17. Testing

- **Automated:** boot the ISO in QEMU (`run_archiso -i out/*.iso` or plain `qemu-system-x86_64 -audiodev pa,...`). Check that `espeakup` is active via `systemctl is-active`, run the installer non-interactively with a test config, boot the installed image, and assert that GDM's dconf has the screen reader enabled and that `yay --version` works for the new user.
- **Speech capture:** route QEMU audio to a WAV file and check that it isn't silent at key points (boot menu, installer prompt, GDM, desktop).
- **Audio coexistence:** in the installed image, assert that `pactl info` reports PulseAudio, `pipewire-pulse` is absent, `$XDG_SESSION_TYPE` is `wayland`, and speech keeps working after switching between a TTY and the desktop (Ctrl+Alt+F3, then back).
- **Manual (essential):** a full install with the monitor off, using only speech, on real hardware, including USB audio and Bluetooth headphones. Ideally with blind testers from the community (e.g. the Arch accessibility mailing list or the Orca users list).

### 18. README: explanation and setup commands

The README is the entry point. A blind user will read it with a screen reader before they have a working Blinux, so it has to stand on its own. As each piece of the plan lands, **the README must be updated** with a plain-language explanation and the exact sequence of commands to run, in order. Use plain text and fenced code blocks, with no images, badges-only info or tables that are required to follow along. Sections to add:

1. **What Blinux is**: a short explanation of the components (espeakup, Orca, GNOME on Wayland, the PulseAudio + PipeWire setup, Emacspeak, AsTeR, zsh, yay) and what is base vs optional.
2. **Building the ISO** (on an existing Arch machine):
   ```sh
   sudo pacman -S --needed archiso devtools git
   git clone https://github.com/OrghoN/Blinux.git
   cd Blinux
   ./scripts/build-repo.sh      # builds yay, emacspeak, dectalk, aster-math, blinux-* into ./repo
   sudo ./scripts/build-iso.sh  # runs mkarchiso, writes out/blinux-*.iso
   ```
3. **Writing the USB stick**: `lsblk`, then `sudo dd if=out/blinux-<date>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync`, with a warning about choosing the right device.
4. **Booting and installing**: what you'll hear (the boot menu defaults to speech after a short timeout), then `blinux-install`, and a list of every question it asks (disk, encryption, console speech, user, microcode, graphics driver/CUDA, optional stacks, dotfiles).
5. **After first boot**: commands for each opt-in:
   ```sh
   sudo blinux-console-speech enable     # espeakup on the TTY via PulseAudio
   sudo blinux-drivers                    # switch to NVIDIA / NVIDIA + CUDA later
   sudo pacman -S blinux-hep blinux-ml   # optional stacks
   sudo pacman -S blinux-aster           # AsTeR spoken math
   git clone https://github.com/OrghoN/.dotfiles ~/.dotfiles   # then that repo's bootstrap
   ```
6. **Building Emacspeak and AsTeR by hand**: Raman's command sequences from "Emacs, Emacspeak and AsTeR", with links to the manual and blog post, for people who aren't on Blinux.
7. **Troubleshooting audio**: `pactl info`, `systemctl --user status pulseaudio speech-dispatcher`, `systemctl status espeakup`, `alsamixer` unmute, and how to tell PipeWire's video role apart from PulseAudio's audio role.

Write the commands only once the scripts exist, and keep them in sync. Each PR that adds or changes a script must update the README's command sequence (add a checklist item to the PR template). The release gate (milestone 7) includes a check that a screen-reader user can follow the README from start to finish.

### 19. Suggested order of work

1. Scaffold the repo, copy `releng`, build an unmodified ISO in CI. Set up the `[blinux]` repo with `yay` as its first package and add it to the ISO.
2. Make speech the default boot entry; verify in QEMU.
3. Harvest and sort the package lists.
4. Write `blinux-config` (including the audio and Wayland configs); verify Orca at GDM and in the session on a manual Arch install, and test the espeakup opt-in.
5. Write `blinux-install` (Option A).
6. Package Emacspeak (Raman's `make config && make`, espeak server); test coding in Emacs.
7. Package Software DECtalk and aster-math; test AsTeR on a LaTeX paper; enable SRE math in the base stack.
8. Add the dotfiles hook.
9. Add the `blinux-base` and optional meta-packages, the driver/CUDA installer step and `blinux-drivers`.
10. Automated QEMU tests, then a full test with the screen off.
11. Update the README with the explanation and the full command sequence (build → USB → install → post-install → troubleshooting). Follow it with only a screen reader to check it, then make the first tagged release.

Throughout: every step above that adds a script or user-facing command also updates the README in the same commit.
