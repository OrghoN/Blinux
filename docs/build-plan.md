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
| 4 | Technical reading | Aster (Emacspeak's audio math/doc layer) working on LaTeX/TeX docs |
| 5 | Dotfiles integration | Installer optionally clones and applies `OrghoN/.dotfiles` |
| 6 | HEP + ML stacks | ROOT, Geant4, Python scientific stack, PyTorch/JAX, CUDA option |
| 7 | Release | Signed ISO, checksums, docs, accessibility test pass |

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

- **Emacspeak and Aster are AUR or not packaged at all.** Aster in particular is old and may need porting or reviving. A PKGBUILD has to be maintained.
- **Audio contention.** espeakup (a root system service), speech-dispatcher, PulseAudio and PipeWire all touch the sound card. The author's machine runs them side by side. Blinux reproduces that exact setup (see "Audio and speech") instead of inventing a new one, but the GDM-to-session and TTY-to-desktop hand-offs still need testing on every release.
- **Wayland gaps.** Blinux is Wayland-only: GNOME on Wayland, with XWayland for X11 apps, and no Xorg session. Orca on Wayland still has a few gaps (some global keyboard grabs and apps that are only half Wayland-native). Track them in Orca's issue tracker instead of shipping an X11 fallback.
- **CUDA and proprietary drivers** can't be shipped freely in every configuration. Make them an install-time choice.
- **ISO size.** ROOT, Geant4 data files, PyTorch and CUDA are huge. Consider a "base" ISO with an optional stack you pull after install.

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
│   ├── base.txt               # core system
│   ├── accessibility.txt      # orca, espeakup, speech-dispatcher, brltty, ...
│   ├── desktop.txt            # gnome + gdm
│   ├── dev.txt                # git, compilers, emacs, zsh, ...
│   ├── hep.txt                # root, geant4, ...
│   ├── ml.txt                 # python-pytorch, jupyter, ...
│   └── aur.txt                # emacspeak, aster, oh-my-zsh-git, ...
├── pkgbuilds/                 # PKGBUILDs for the [blinux] repo
│   ├── yay/                   # AUR helper, prebuilt so it's there from first boot
│   ├── emacspeak/
│   ├── aster/
│   └── blinux-config/         # meta + config package (see the `blinux-config` section)
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

Then sort by hand into the `packages/*.txt` files. Drop anything hardware- or machine-specific: microcode, GPU drivers, laptop tools, personal apps. Hardware-specific packages become installer questions (e.g. `intel-ucode` vs `amd-ucode`, `nvidia` vs `mesa`). A `harvest-packages.sh` script can diff the machine against the current lists over time so new useful packages get flagged.

### 3. Live ISO (archiso)

- Start from `releng`: `cp -r /usr/share/archiso/configs/releng profile/`.
- The Arch ISO already ships `espeakup` and has an accessible boot entry ("Arch Linux install medium with speech"). In Blinux, **make the speech entry the default** and give the menu a short timeout, so a blind user just waits and gets speech.
- Add to `packages.x86_64`: `espeakup`, `espeak-ng`, `alsa-utils`, `brltty` (braille displays), `archinstall`, `zsh`, `git`, `base-devel`, `yay` (from `[blinux]`).
- Set the default shell in the live environment to zsh with a minimal, screen-reader-friendly prompt (no Unicode glyphs or right-side prompts, which screen readers read badly).
- A welcome message, read aloud on login, explains how to start the installer: `blinux-install`.
- Build: `mkarchiso -v -w /tmp/archiso-work -o out/ profile/`.

### 4. Audio and speech

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

### 5. Display: Wayland with XWayland

- GNOME runs on Wayland only. GDM keeps `WaylandEnable=true` (the default). Ship no Xorg session and don't install `xorg-server`.
- `xorg-xwayland` is always installed (it's on the author's machine too) so X11-only apps keep working inside the Wayland session, e.g. ROOT's X11 GUI (`TBrowser`, canvases), older Java/Tk apps and some HEP event displays. AT-SPI works for X11 apps under XWayland too, so Orca can still read them.
- Set `QT_QPA_PLATFORM=wayland;xcb` and `MOZ_ENABLE_WAYLAND=1` (already the default in current Firefox) in `/etc/environment.d/` so toolkits use Wayland first and fall back to X11.
- With NVIDIA proprietary drivers (see "Hardware drivers and CUDA"), `nvidia_drm.modeset=1` must be set. Otherwise GDM's udev rule quietly disables Wayland and the user lands in a session Blinux doesn't support.

### 6. `blinux-config` meta package

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

### 7. Installer

**Option A (recommended to start):** a `blinux-install` shell script that wraps `archinstall` with a JSON config (`--config blinux.json`). Use `archinstall`'s menu-free mode, with the script asking the few required questions through plain line-by-line `read` prompts. These work well with espeakup; curses menus don't.

Questions to ask:
1. Target disk (list with size and model, read aloud, confirm twice).
2. Encryption yes/no, and the passphrase.
3. Console speech on the installed system (espeakup through PulseAudio)? Default no, matching the author's machine.
4. Username, password and hostname.
5. Hardware: CPU microcode, GPU (mesa / nvidia / nvidia + CUDA).
6. Optional stacks: HEP, ML, both, neither.
7. Clone `OrghoN/.dotfiles`? (y/n, plus a custom URL.)

Then: partition → pacstrap base + `base-devel` + `git` + `yay` + `blinux-config` + chosen stacks → bootloader (systemd-boot or GRUB) → enable `gdm`, `NetworkManager`, `bluetooth` (and `espeakup` only if the user asked for console speech) → copy the audio mixer state (`alsactl store`) so volume isn't muted on first boot → speak "Installation complete, remove the media and press Enter to reboot."

**Option B (later):** a custom Python installer built on the `archinstall` library, for better error handling and progress that's spoken aloud.

### 8. Shell: zsh and oh-my-zsh

- Install `zsh`, and `oh-my-zsh-git` from the AUR (repackaged in `[blinux]`) or vendor it into `/usr/share/oh-my-zsh`.
- Theme: a plain-ASCII prompt. Avoid `agnoster`, `powerlevel10k` and right prompts (RPROMPT), which clutter speech output.
- Useful plugins: `git`, `sudo`, `history-substring-search`, `zsh-autosuggestions` (consider disabling it by default, since inline suggestions can be noisy with speakup).

### 9. AUR helper: yay

`yay` is part of the system from the start, so the user never has to bootstrap it by hand. Bootstrapping means cloning, `makepkg` and reading build output by ear, which is the kind of fiddly first-boot task Blinux exists to remove.

- **How it ships:** build `yay` (or `yay-bin`) from its AUR PKGBUILD in a clean chroot and publish it in the `[blinux]` repo (see "Custom repository"). It then installs with plain `pacman`, on the live ISO and through `pacstrap` on the target, and doesn't need to be compiled during install. Bump it with the monthly CI rebuild.
- **Dependencies:** `base-devel` and `git` are always installed, because yay needs them to build anything from the AUR.
- **Default config:** `blinux-config` ships `/etc/skel/.config/yay/config.json` with output that reads better through a screen reader, e.g. `"diffmenu": false`, `"editmenu": false`, `"cleanAfter": true`, `"answerclean": "None"` and `"removemake": "yes"`. This cuts down interactive menus. The user can still review PKGBUILDs with `yay -G` or `yay --editmenu`.
- **Sudo:** the installer adds the user to `wheel` and enables `%wheel ALL=(ALL:ALL) ALL` in `/etc/sudoers.d/10-wheel`, so yay can call `pacman`.
- **Post-install stacks:** the HEP/ML bundles that need AUR packages (e.g. `geant4`, `delphes`) can be installed after setup with `yay -S blinux-hep`. They also come prebuilt in `[blinux]`, so yay mostly handles the user's own extras.
- **Test:** after install, run `yay -S --noconfirm` on a small AUR package as the new user in the QEMU test.

### 10. Emacs, Emacspeak and Aster

- `emacs` (official repo) and `emacspeak` (AUR, rebuilt into `[blinux]`). Emacspeak needs a speech server: use the `espeak` server or `espeakup`-compatible TTS so the voice matches the rest of the system.
- A site-start snippet: `(load "/usr/share/emacs/site-lisp/emacspeak/lisp/emacspeak-setup.el")`, gated on an env var so it can be turned off.
- **Aster** (Audio System for Technical Readings, T.V. Raman) is historic and not packaged. Plan:
  1. Find out what's current. Much of Aster's capability lives on inside Emacspeak (e.g. `emacspeak-maths` with the MathJax/speech-rule-engine backend).
  2. Package `speech-rule-engine` (Node) and Emacspeak's maths server for spoken LaTeX/MathML.
  3. If the original Aster code is still wanted, fork it into `pkgbuilds/aster/` and port it to current Emacs.
- Also consider adding `texlive`, `pandoc`, `brltty` and `liblouis` for braille and document conversion.

### 11. Dotfiles integration

- The installer clones `https://github.com/OrghoN/.dotfiles` into `~/.dotfiles` as the new user and runs its bootstrap (stow, chezmoi, a script, whatever the repo uses).
- Blinux defaults should live in `/etc/skel` and `/etc` (system level), so user dotfiles override them cleanly without conflicts.
- Coordinate: anything accessibility-critical (Orca enabled, speech-dispatcher config) stays system-level, so a broken dotfile can't make the machine silent.

### 12. HEP and ML stacks

**HEP (`packages/hep.txt`)**
- `root` (already on the author's machine), `geant4` + datasets (AUR, large), `hepmc3`, `pythia8`, `fastjet`, `lhapdf`, `delphes` (AUR), `python-uproot`, `python-awkward`, `python-hist`, `python-scikit-hep` bits.
- `gcc`, `clang`, `cmake`, `ninja`, `gfortran`, `boost`, `eigen`, `gsl`.

**ML (`packages/ml.txt`)**
- `python`, `python-pip`, `python-numpy`, `python-scipy`, `python-pandas`, `python-scikit-learn`, `python-matplotlib`, `jupyterlab` (note: Jupyter's web UI has mixed screen-reader support. Also provide `emacs-jupyter` / `ein` and plain `ipython`).
- `python-pytorch` / `python-pytorch-cuda`, `python-jax`, `cuda` and `cudnn` (only when the NVIDIA option is chosen).
- `uv` or `python-poetry` for per-project environments, `conda`/`micromamba` optional for HEP compatibility.

**Accessible plotting:** matplotlib output is visual. Include tools that make data readable without sight, e.g. `python-sonification` libraries (`astronify`, `sonify`), and make sure tabular summaries and `rich`/plain-text output are easy to get.

Ship these as **meta-packages** (`blinux-hep`, `blinux-ml`) so they can be installed after setup and kept out of the base ISO if size is a problem.

### 13. Custom repository `[blinux]`

- Build AUR and custom PKGBUILDs in a clean chroot (`extra-x86_64-build` from `devtools`).
- Sign packages with a dedicated GPG key, and generate the db with `repo-add -s blinux.db.tar.zst *.pkg.tar.zst`.
- Host it on GitHub Releases or Pages and add it to `pacman.conf`, for both the ISO and installed systems.

### 14. CI and builds

- A GitHub Actions workflow running in an `archlinux:latest` container (needs `--privileged` for mkarchiso):
  1. Build the `[blinux]` repo packages.
  2. Run `mkarchiso`.
  3. Upload the ISO + `sha256sums` + signature as an artifact or release.
- Monthly scheduled rebuild to track Arch updates.

### 15. Testing

- **Automated:** boot the ISO in QEMU (`run_archiso -i out/*.iso` or plain `qemu-system-x86_64 -audiodev pa,...`). Check that `espeakup` is active via `systemctl is-active`, run the installer non-interactively with a test config, boot the installed image, and assert that GDM's dconf has the screen reader enabled and that `yay --version` works for the new user.
- **Speech capture:** route QEMU audio to a WAV file and check that it isn't silent at key points (boot menu, installer prompt, GDM, desktop).
- **Audio coexistence:** in the installed image, assert that `pactl info` reports PulseAudio, `pipewire-pulse` is absent, `$XDG_SESSION_TYPE` is `wayland`, and speech keeps working after switching between a TTY and the desktop (Ctrl+Alt+F3, then back).
- **Manual (essential):** a full install with the monitor off, using only speech, on real hardware, including USB audio and Bluetooth headphones. Ideally with blind testers from the community (e.g. the Arch accessibility mailing list or the Orca users list).

### 16. Suggested order of work

1. Scaffold the repo, copy `releng`, build an unmodified ISO in CI. Set up the `[blinux]` repo with `yay` as its first package and add it to the ISO.
2. Make speech the default boot entry; verify in QEMU.
3. Harvest and sort the package lists.
4. Write `blinux-config` (including the audio and Wayland configs); verify Orca at GDM and in the session on a manual Arch install, and test the espeakup opt-in.
5. Write `blinux-install` (Option A).
6. Package Emacspeak; set up the speech server; test coding in Emacs.
7. Look into Aster and maths speech; package what works.
8. Add the dotfiles hook.
9. Add the HEP/ML meta-packages.
10. Automated QEMU tests, then a full test with the screen off, then the first tagged release.
