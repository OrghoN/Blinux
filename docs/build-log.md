# Blinux Build Log

What was built from [build-plan.md](build-plan.md) on 2026-11-25, how it was checked, and what is still open.

## Summary

All 12 steps of the plan's "Suggested order of work" are implemented, in 13 commits. The repository now contains:

- **A talking live ISO.** The stock Arch `releng` archiso profile, with the speakup speech entry as the default in systemd-boot, syslinux and GRUB (5-second timeout). The welcome message is plain text and points to the installer. The base stack is carried on the ISO as an offline package cache.
- **`blinux-install`, the talking installer.** It asks one question at a time, reads every option aloud with its number, requires the disk to be confirmed twice, and reads back a summary before anything changes. It also runs unattended from a JSON config.
  - It partitions for UEFI (systemd-boot) or BIOS (GRUB), with optional LUKS2.
  - It installs the base stack offline, then downloads the install-time choices when there's a network: NVIDIA, NVIDIA + CUDA, the optional stacks and broadcom-wl.
  - It sends pacman's output to a log and speaks a short line for each step, instead of having speakup read thousands of lines aloud.
- **Packages in `[blinux]`:**
  - `blinux-tools`: the installer and helpers
  - `blinux-config`: all system configuration
  - `blinux-meta`: the base stack and the aster, docs, hep, ml and ml-cuda stacks, generated from `packages/*.txt`
  - `emacspeak` and `aster-math`: built per T.V. Raman's instructions
  - `blinux-keyring`: the signing key, built once you add your key
  - 11 AUR packages, pinned to exact AUR commits in `packages/aur.lock`
- **Helpers:**
  - `blinux-console-speech` (espeakup through PulseAudio, opt-in)
  - `blinux-drivers` (switch graphics drivers after install)
  - `blinux-dotfiles` (clones and links `OrghoN/.dotfiles` as the user)
  - `blinux-aster-setup` (builds DECtalk locally; see below)
- **A six-layer testing suite**, all driven by `make` targets:
  - static checks of package lists, configs and README commands
  - 71 bats unit tests
  - a 48-combination package resolution matrix and package smoke tests
  - a QEMU/KVM harness that records the guest's audio and checks it with speech-to-text
  - AT-SPI and Orca tests
  - a manual screen-off release checklist
- **GitHub Actions:**
  - `ci.yml`: pull requests and main
  - `testing-repo.yml`: CD to `[blinux-testing]`
  - `nightly.yml`
  - `upstream.yml`: weekly version bumps as a pull request
  - `release.yml`: signed packages and ISO, the full suite on the release ISO, then a draft release
- **The README:** a full explanation and the command sequence, from building the ISO through to troubleshooting audio.

**What I verified here:**
- All lint checks and unit tests pass locally.
- Emacspeak 60.0 and aster-math were built for real with `makepkg`, and both pass their `check()`.
- Every Blinux data package was built and its contents inspected.
- The AUR resolver ran live against the AUR.

**Not run here:** anything that needs root or KVM. That means the clean-chroot builds, the ISO build, the QEMU tests and the package smoke tests. They're written and wired into CI, but haven't run yet. The [open items](#open-items) section lists what to do first.

---

## Conceptual take

### What guided the choices

1. **Copy what already works on the author's machine.** The audio setup is the clearest case. Your machine runs PulseAudio as the sound server (`pactl info` reports `Server Name: pulseaudio`), PipeWire with `pipewire-media-session` for screen capture and video, no `pipewire-pulse` or WirePlumber, speech-dispatcher active, and espeakup installed but disabled. Blinux ships exactly that, and the lint step fails if `pipewire-pulse`, `wireplumber` or `xorg-server` ever appear in a package list. The package lists started from your 203 explicitly installed packages. Every one of them is now either in a stack or in `packages/ignore.txt`, and `scripts/harvest-packages.sh` keeps that true over time.
2. **Speech at every step, and tests that listen for it.**
   - Every accessibility promise has a check: speech is the boot default, Orca runs at the greeter, the TTY hand-off keeps speech going, and there are no long silences after an action. The static checks cover the configuration.
   - The QEMU tests record the guest's sound card to a WAV file. They measure how much of it is speech, and run offline speech-to-text to check what was said.
   - Everything the tools print is plain text, one idea per line, with no escape codes. A unit test enforces this.
3. **One code path for people and for tests.** Interactive answers and `--config` both produce the same JSON config, validated against `tools/share/install-config.schema.json`. All hardware detection reads from files that tests can replace: recorded `lspci`, `/proc/cpuinfo` and `lsblk` output from real machines, including yours. So the unit tests run exactly the code a real install runs.
4. **Respect upstream, and its licences.**
   - Emacspeak and AsTeR follow Raman's own steps, in his directory layout.
   - AUR packages are pinned, so CI never builds whatever an AUR maintainer pushed most recently. Bumps arrive as reviewable pull requests.
   - Software DECtalk's licence is proprietary, so Blinux never redistributes it.
5. **Nothing exists only in YAML.** Every CI job calls a `make` target, so any failure can be reproduced locally with the same command.

### Where the implementation differs from the plan, and why

| Plan said | Implemented | Why |
|-----------|-------------|-----|
| Wrap `archinstall` with a JSON config | Own installer using `sgdisk`, `cryptsetup`, `pacstrap`, `bootctl` and GRUB | archinstall's config format changes between releases and can't be unit-tested offline. Blinux needs to control what is spoken at every step, and to keep pacman output out of speakup's path. |
| Emacspeak in `/usr/share/emacs/site-lisp/emacspeak` | `/opt/emacspeak`, with AsTeR at `/opt/emacspeak/aster-math` | Raman's instructions load Emacspeak from its own tree, and your `init.el` loads `/opt/emacspeak/lisp/emacspeak-setup.el` and `/opt/emacspeak/aster-math/ui/aster.el`. So your dotfiles work unchanged. |
| A separate `speech-rule-engine` package | Emacspeak's `js/node` math server, with `npm ci` from Raman's own `package-lock.json` | That's how Raman's `js/node/Readme.org` sets it up. MathJax and the Speech Rule Engine are pinned by upstream's lock file. |
| `dectalk` package in `[blinux]` | Local build only, through `blinux-aster-setup` | DECtalk's `LICENCE`: "Possession, use, or copying of this software ... is authorized only pursuant to a valid written license from FONIX." Publishing binaries would be redistribution. The command explains this and asks before building anything. |
| `pkgbuilds/yay` | yay built from its AUR recipe, pinned in `aur.lock` | It's the same result without keeping a copy of yay's PKGBUILD in sync by hand. |
| JAX in `blinux-ml`; uproot, awkward and hist in `blinux-hep` | Left out and documented: install them from PyPI with `uv pip install` | `python-jaxlib` compiles XLA from source. The scikit-hep AUR packages are flagged out of date, and awkward's needs the whole CUDA toolkit to build. The PyPI wheels install in seconds. |
| Publish the stable repo, then build the ISO and test it | Build and test first; publish the stable repo only after the release ISO passes | A failing release candidate should never reach installed systems through `pacman -Syu`. |
| `iwd` in the base stack | Live ISO only | NetworkManager manages Wi-Fi on the installed system. |
| `broadcom-wl` never on the ISO | Kept on the live ISO only | The stock Arch ISO ships it so Broadcom Wi-Fi works in the live system. It stays out of the installed base unless the installer detects the card and asks. |

---

## Technical details

### Step by step

**1. Scaffold** (`6ef09ca`)
- `profile/` is a copy of archiso 88's `releng`, rebranded.
- **Makefile:** every target the plan names, with `STRICT=1` for CI.
- **`scripts/build-repo.sh`:**
  - It builds AUR packages from `aur.lock`, then `pkgbuilds/ORDER`, in a devtools clean chroot. The chroot sees the local `[blinux]` repo, so packages can depend on each other.
  - Already-built versions are skipped.
  - Packages are signed when `GPGKEY` is set.
  - `--mode nodeps` builds the data-only packages without root.
- **`scripts/build-iso.sh`:** adds the local repo and `packages/iso.txt` to the profile. It downloads the whole `blinux-base` dependency closure, plus microcode and open-source drivers, into `airootfs/opt/blinux/offline-repo` (`pacman -Syw` with an empty `--dbpath`). Then it runs `mkarchiso`, writes checksums, and warns when the ISO is over 2 GiB.
- **`scripts/aur-resolve.py` and `aur-lock.sh`:** resolve the AUR closure through the AUR's RPC interface, sort it in dependency order, and pin each AUR commit.
- **`scripts/repo-release.sh`:** fetches and publishes pacman repos stored as GitHub Release assets.
- **`scripts/ci/*`:** a privileged Arch container runner, signing-key import with the passphrase cached in gpg-agent (so `repo-add -s` works), disk cleanup and KVM enablement.
- **`ci.yml` and `testing-repo.yml`:** every action is pinned to a commit SHA (all releases more than two weeks old), with Dependabot and a PR template.

**2. Speech by default** (`dfb1489`)
- systemd-boot: `default 02-archiso-speech-linux.conf`, `timeout 5`, with the speech entry sorted first.
- syslinux: `DEFAULT archspeech`, `TIMEOUT 50`.
- GRUB (both `grub.cfg` and `loopback.cfg`): `default=archlinux-accessibility`, `timeout=5`, with the speech entry listed first.
- The motd is plain text with no ANSI colour codes, which speakup would read aloud. The root prompt is `%~ %#`.

**3. Package lists** (`660a397`)
- **The stack lists:** `base.txt` (70 entries, with `@gnome` expanded at generation time), plus `aster`, `docs`, `hep`, `ml` and `ml-cuda`.
- **The install-time choices:** `microcode`, `drivers-open`, `drivers-nvidia` and `cuda`.
- **The rest:** `iso`, `aur`, and `ignore` (personal apps, fonts and extra kernels from your machine).
- **Additions from harvesting your machine:**
  - `sof-firmware`: your audio chip, `skl_hda_dsp_generic`, needs it, and many Intel laptops have no sound without it.
  - `evince`, `gnome-terminal`, `localsearch` and `tclx`.
  - `cl-asdf-flv` (in the AsTeR stack), and `texlive-binextra` and `texlive-pictures` (in the docs stack).

**4. `blinux-config`** (`6f20d58`)
- **dconf:** the screen reader on at the greeter (`/etc/dconf/db/gdm.d`) and in every session (`local.d`), animations off, and a larger cursor. `dconf update` runs from the package's install script.
- **Speech:** a speech-dispatcher `clients/00-blinux.conf` with `AudioOutputMethod "pulse"` and eSpeak NG. It's included from `speechd.conf`, so the file owned by the speech-dispatcher package isn't edited.
- **Wayland:** `/usr/lib/environment.d/50-blinux-wayland.conf` sets `QT_QPA_PLATFORM=wayland;xcb`, `MOZ_ENABLE_WAYLAND` and Qt's AT-SPI switches.
- **Shell and sudo:** the `/etc/skel` zsh setup (system oh-my-zsh, no theme, a plain prompt, `SINGLE_LINE_ZLE` on the console), a yay config with no menus, and a sudoers drop-in for `wheel`.
- **Emacs:** a `site-start.el` that loads `site-start.d/*.el`.
- **Console speech templates:** `blinux-console-speech enable` writes a PulseAudio drop-in, which loads `module-native-protocol-unix auth-anonymous=1 socket=/tmp/blinux-pulse.sock`, and an espeakup drop-in setting `PULSE_SERVER=unix:/tmp/blinux-pulse.sock`. It then enables espeakup.

**5. Installer** (`c76a346`)
- **Libraries:** `tools/lib/common.sh` (prompts, `runcmd` and dry-run handling), `detect.sh`, `drivers.sh`, `packages.sh` and `install.sh` (the 11 steps).
- **Detection:**
  - GPUs are read from `lspci -mm -nn`. NVIDIA cards count as Turing or newer when the chip name starts with TU, GA, AD, GH or GB; older cards don't get `nvidia-open`.
  - Broadcom Wi-Fi is vendor `14e4` with class `0280`.
  - Disks come from `lsblk -J`, skipping the live medium, loop devices, zram and optical drives.
- **Partitioning:**
  - UEFI: a 1 GiB ESP, then the root partition.
  - BIOS: a `bios_grub` partition, a 1 GiB `/boot`, then root, so encrypted BIOS installs don't need GRUB to unlock anything.
- **Encryption:** the `encrypt` mkinitcpio hook, with `cryptdevice=UUID=...:blinuxroot`.
- **Accounts:** root is locked and the user is in `wheel`.
- **Package repo:** the installed system gets `/etc/pacman.d/blinux.conf` for `[blinux]`.
- **A bug found while writing it:** `cryptsetup` was first piped through the background "still working" wrapper. Bash gives background jobs `/dev/null` as stdin, so the passphrase would have been lost. Encryption now runs in the foreground.

**6. Emacspeak** (`57d1e45`)
- The package builds 60.0 (the newest release, above AsTeR's "57.0 or later") with `make config && make` and `make -C servers/native-espeak`, then runs `npm ci` in `js/node`.
- `check()` loads `tclespeak.so` into `tclsh`, checks that MathJax and the Speech Rule Engine load, and loads `emacspeak-setup.el` in batch Emacs.
- I dropped `emacspeak-preamble.elc`, because it had the build directory baked into `emacspeak-xslt-directory`. A test of the relocated tree then computed the right path.
- `50-emacspeak.el` skips loading Emacspeak if your own init already loads `emacspeak-setup`, as your dotfiles do, or if `BLINUX_NO_EMACSPEAK` is set.

**7. AsTeR** (`a93e3bc`)
- aster-math is pinned to commit `8e4e4dd` (2023-08-17), installed to `/opt/emacspeak/aster-math`, and built with `sbcl --script aster.lisp` plus the flex lexer.
- The lexer is K&R-era C, which GCC 15's C23 default rejects (`error: prototype declaration`), so it's built with `-std=gnu17`. The local build works, and the lexer turns `$x^2$` into `(inline-math "x" "^" (math-number "2"))`.
- **DECtalk is never built or published by Blinux.** `tools/share/local-pkgbuilds/` holds two build recipes, `dectalk` and `emacspeak-dtk-server`, which `blinux-aster-setup` builds with `makepkg -si` on the user's machine after the licence notice.
  - `dectalk` uses the `develop` branch (which Raman's notes and the DECtalk README both name), installs to `/opt/dectalk`, and uses Emacspeak's `DECtalk.conf`.
  - It includes the same toolchain fixes the AUR recipe applies, plus `-std=gnu17`.
- **Resolver fixes:**
  - It no longer follows `checkdepends`, which formed a cycle through `python-awkward` and `python-hist`; AUR packages now build with `--nocheck`.
  - It resolves names with `pacman -Sp -dd`. Without `-dd`, pacman computed a whole transaction against your machine, which is part-way through an upgrade, so `gcc-fortran` and `glibc` looked missing and were "provided" by junk AUR packages (`gcc-git`, `glibc-eac`).

**8. Dotfiles** (`234cfee`)
- `blinux-dotfiles` always runs as the user. The installer calls it with `arch-chroot ... runuser -l USER -c 'blinux-dotfiles --as-user ...'`.
- If the repo has its own `blinux-bootstrap`, `bootstrap.sh`, `install.sh` or `setup.sh`, it runs that and stops.
- Otherwise it links files the way your dotfiles README does:
  - dotfiles to `~/`
  - `init.el` to `~/.emacs.d/`
  - `*.zsh` and `custom/*.zsh` to `~/.oh-my-zsh/custom/`
- Anything it replaces is kept as `NAME.blinux-backup`.
- It copies the system oh-my-zsh to `~/.oh-my-zsh` and links powerlevel10k into it, because your `.zshrc` expects both there. It also adds `export dotfiles=...` to `~/.zshenv`.

**9. Meta-packages and drivers** (`bcbf207`)
- `scripts/gen-meta.sh` generates the `blinux-meta` package from the stack lists. Groups are expanded, because a pacman dependency can't name a group.
- `pkgrel` is bumped only when the dependency set changes. `--check` is part of `make lint`.
- `blinux-ml-cuda` depends on `blinux-ml` plus `python-pytorch-cuda`, which provides `python-pytorch`.
- `blinux-drivers` switches drivers both ways:
  - It adds or removes `nvidia_drm.modeset=1` on systemd-boot entries or GRUB's defaults.
  - It adds or removes the `mkinitcpio.conf.d` modules drop-in and a pacman hook that rebuilds the initramfs.
  - It records the choice in `/etc/blinux/graphics`.

**10. Testing suite** (`d7e96e7`, `92fe236`)
- **Layer 1:** `check-package-lists.sh` (the deny-list, nothing proprietary in base, the base essentials, no duplicates, every package exists), `check-configs.sh`, and `check-readme-commands.sh`.
  - `check-configs.sh` checks that dconf compiles, sudoers parses, Elisp byte-compiles and zsh parses. It also checks that drop-ins and hooks are well-formed, that the fixtures match the schema, that speech is the boot default in all three loaders, and that nothing sets `WaylandEnable=false`.
  - `check-readme-commands.sh` checks that README shell blocks parse and name real scripts, tools and make targets.
- **Layer 2:** 71 bats tests in 9 files. While writing them I found that bats's own `run` was being shadowed by the tools' `run` helper, so the helper is now `runcmd`.
- **Layer 3:** `resolve-matrix.sh` and `smoke.sh`.
- **Layer 4:** `tests/harness/` drives QEMU over the serial console (pexpect) and QMP. The audio analyser measures speech, its start and the gaps, and is tested against synthetic WAVs. Speech-to-text uses Vosk's small model.
  - The unmodified ISO is booted with no key pressed and must speak.
  - Scripted runs boot the ISO's own kernel with `console=ttyS0` added.
  - Each install fixture is installed, then first-booted in two phases. First the greeter must have Orca and audible speech. Then a test-only GDM autologin runs the session checks: Wayland, XWayland started on demand by a Tk client, PulseAudio with no `pipewire-pulse`, speech-dispatcher audible, the TTY hand-off, and checks for each case.
- **Layer 5:** `tests/guest/a11y_check.py` walks the AT-SPI tree of Text Editor, Console, Files and Settings. Other tests check Orca's `--debug-file` log for a scripted focus path, that Emacspeak speaks, and the longest silence.
- **Layer 6:** `tests/manual/release-checklist.md`.

**11. CD** (`c899d03`)
- `nightly.yml`: rebuild everything with `--force`, heavy smoke tests, the QEMU matrix and a11y, and a `nightly-failure` issue kept open while anything fails.
- `upstream.yml`: `scripts/bump-upstream.sh` checks Emacspeak releases (nvchecker), aster-math and DECtalk commits, and re-pins the AUR lock, then opens a pull request.
- `release.yml`: refuses to run without `keys/blinux.asc`. It builds and signs, builds the ISO, enforces the 2 GiB asset limit, runs the full suite on that ISO, publishes the stable repo, and creates the draft release with the checklist attached.
- The `blinux-keyring` package and `keys/README.md`.

**12. README** (`bb546fa`): explanation, then commands: build, verify, USB, every installer question, post-install, Emacspeak and AsTeR (Raman's steps written out), test layers, repos, and audio troubleshooting.

### How it was verified

| Check | Result |
|-------|--------|
| `make lint` (shellcheck, package lists, configs, meta in sync, README commands) | Pass. shfmt, markdownlint and lychee aren't installed here, so they were skipped; CI installs them with `STRICT=1`. |
| `make unit` (bats) | 71 of 71 pass |
| Emacspeak 60.0 `makepkg` and `check()` | Pass. Relocated-tree test pass. Package is 8.7 MB. |
| aster-math `makepkg` and `check()` | Pass |
| blinux-tools, blinux-config and blinux-meta (`build-repo.sh --mode nodeps`) | Pass, contents inspected |
| AUR resolver and lock, run live | 11 package bases, in dependency order |
| Installer dry runs (all 7 fixture cases plus interactive) | Pass, as part of the unit tests |
| Install config schema (draft 2020-12) | Valid. Rejects root as the user name, and encryption without a passphrase. |
| Workflow YAML | Parses; jobs wired as designed |
| Audio analyser self-tests (pytest) | 3 of 3 pass |
| Clean-chroot builds, ISO build, QEMU tests, smoke tests | **Not run**: these need root and KVM |
| DECtalk local recipe | **Not run**, given the licence |

---

## Open items

What still needs to be done, in rough order:

1. **Run CI for real.** Push a branch and watch `ci.yml`. Expect to fix things in the parts that couldn't run here: the clean-chroot builds (especially geant4's build time), the offline cache, `mkarchiso`, and the QEMU harness's serial console and audio timing. Recorded audio, serial logs and screenshots land in the job artifacts.
2. **Create the signing key and the GitHub environments**, as `keys/README.md` describes: the `release` environment with a required reviewer, and the `testing` environment with a subkey. Then commit `keys/blinux.asc` and change `SigLevel` in the installer's `blinux.conf` from `Optional TrustAll` to `Required` (it's marked `TODO(v0.1.0)`).
3. **Turn on branch protection for `main`**, requiring `lint`, `unit`, `packages`, `iso` and `integration-smoke`. The `gh` CLI isn't installed here, so I couldn't do it.
4. **Things that need real hardware:**
   - The console-speech PulseAudio socket design, especially whether espeak-ng falls back to ALSA cleanly when no one is logged in.
   - Whether speech-dispatcher honours global settings in `clients/00-blinux.conf`, since that file is pulled in by an `Include` meant for per-client blocks. If it doesn't, move the settings into a `post_install` edit of `speechd.conf`.
   - The GDM-to-session audio hand-off.
5. **ISO size.** The offline cache includes all of GNOME, Emacs and the compilers. Measure the first ISO. If it's over 2 GiB, trim `base.txt`, or host the ISO outside GitHub Releases.
6. **DECtalk recipe.** Run `blinux-aster-setup` once on your machine. The recipe follows Raman's notes and the AUR's fixes but hasn't been run.
7. **Optional:** add a `blinux-bootstrap` script to `OrghoN/.dotfiles`. `blinux-dotfiles` will use it instead of its built-in linking.
8. **Tag `v0.1.0`** once the above is done, and work through `tests/manual/release-checklist.md` with the screen off before publishing the draft.

## Commits

| Commit | Step |
|--------|------|
| `6ef09ca` | Scaffold: archiso profile, Makefile, build scripts, CI and testing-repo workflows |
| `dfb1489` | Live ISO: speech boot entry is the default in every bootloader |
| `660a397` | Package lists: base stack, optional stacks and driver choices |
| `6f20d58` | blinux-config: Orca at login, speech, Wayland, zsh, yay and sudo defaults |
| `c76a346` | blinux-install: the talking installer |
| `57d1e45` | emacspeak: build from source per T.V. Raman, install in /opt/emacspeak |
| `234cfee` | blinux-dotfiles: clone and set up a dotfiles repository as the user |
| `bcbf207` | Meta-packages and blinux-drivers |
| `d7e96e7` | Tests, layers 1-2: static checks and bats unit tests |
| `92fe236` | Tests, layers 3-6: package matrix, QEMU harness, a11y, release checklist |
| `c899d03` | CD: nightly, upstream and release workflows, package signing keyring |
| `bb546fa` | README: explanation and the full command sequence |
| `a93e3bc` | AsTeR: aster-math package, and DECtalk built only on the user's machine |
