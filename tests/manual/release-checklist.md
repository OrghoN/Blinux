# Blinux release checklist (testing layer 6)

Copy this file for each release, fill it in, and attach it to the draft GitHub
Release that `release.yml` creates. Publish the release only when every line
is ticked or has a linked issue.

Release: `vX.Y.Z` &nbsp;·&nbsp; ISO: `blinux-YYYY.MM.DD-x86_64.iso` &nbsp;·&nbsp; Tester:

## Install with the monitor off, using speech only

- [ ] Author's machine: Intel SOF audio, Iris Xe, UEFI. Default boot entry speaks without a key press
- [ ] One AMD machine (open source drivers)
- [ ] One NVIDIA machine, graphics choice 2 (NVIDIA proprietary); GNOME is on Wayland after install
- [ ] One NVIDIA machine, graphics choice 3 (NVIDIA + CUDA); `python -c "import torch; print(torch.cuda.is_available())"` prints True
- [ ] A BIOS (legacy boot) machine or VM
- [ ] An encrypted install: the passphrase prompt at boot is usable without sight
- [ ] An offline install: skipped packages are read out with the catch-up command

## Audio and speech

- [ ] Orca speaks at the GDM login screen and after logging in
- [ ] USB headphones or a USB sound card
- [ ] Bluetooth headphones (pulseaudio-bluetooth)
- [ ] Plugging and unplugging headphones doesn't silence speech
- [ ] Suspend and resume: speech comes back
- [ ] Console speech opt-in (`sudo blinux-console-speech enable`): speech on a TTY, then back on the desktop

## Braille

- [ ] A braille display works through brltty on the console and with Orca

## Editor and technical reading

- [ ] Emacs starts with Emacspeak speaking (eSpeak voice)
- [ ] AsTeR (`M-x load-library RET aster`, `M-x aster`) reads a real HEP paper's LaTeX
- [ ] Emacspeak's math reading (Speech Rule Engine) reads a LaTeX formula

## Stacks

- [ ] `sudo pacman -S blinux-hep` after install; `root -b -q` runs
- [ ] `sudo pacman -S blinux-ml` after install; `python -c "import torch"` works
- [ ] `yay -S` of a small AUR package works as the new user

## README walk-through

- [ ] A screen-reader user followed the README from start to finish (build, USB, install, post-install) without sighted help
- [ ] Every command in the README was run exactly as written

## Community feedback

- [ ] Asked blind testers (Arch accessibility list, Orca users list) to try the release candidate
- [ ] Their reports are filed as issues with the `tester-feedback` label

## Sign-off

- [ ] Automated suite (layers 1-5) passed on this exact ISO in `release.yml`
- [ ] ISO signature verifies: `gpg --verify blinux-*.iso.sig`
