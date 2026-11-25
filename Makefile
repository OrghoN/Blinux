# Blinux build and test entry points. CI runs exactly these targets.
#
#   make lint        static checks (layer 1)
#   make unit        bats unit tests (layer 2)
#   make repo        build the [blinux] package repo (needs sudo + devtools)
#   make packages    build the repo, then package smoke tests (layer 3)
#   make iso         build the ISO (needs sudo + archiso)
#   make test-iso    QEMU boot/install tests against out/*.iso (layer 4)
#   make test-a11y   accessibility tests in the installed desktop VM (layer 5)
#   make ci          what every pull request runs: lint + unit
#   make meta        regenerate pkgbuilds/blinux-meta/PKGBUILD from packages/*.txt
#   make lock        re-resolve and re-pin AUR packages in packages/aur.lock
#
# Set STRICT=1 (CI does) to fail when an optional lint tool is missing.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

PYTHON     ?= python3
BATS       ?= bats
PYTEST     ?= $(PYTHON) -m pytest
STRICT     ?= 0
SUDO       ?= sudo
ISO        ?= $(firstword $(wildcard out/blinux-*.iso))
CASES      ?=
FIRMWARE   ?=
PYTEST_ARGS ?=

SHELL_FILES := $(shell git ls-files 'scripts/*.sh' 'tools/bin/*' 'tools/lib/*.sh' \
	'tests/static/*.sh' 'tests/packages/*.sh' 'config/usr/lib/blinux/*.sh' 2>/dev/null)

.PHONY: help lint lint-shell lint-lists lint-configs lint-meta lint-docs unit \
	repo packages packages-tests iso test-iso test-a11y test ci meta lock clean

help:
	@sed -n '2,/^$$/p' Makefile | sed 's/^# \{0,1\}//'

# ---------------------------------------------------------------- layer 1
lint: lint-shell lint-lists lint-configs lint-meta lint-docs

define optional_tool
	if command -v $(1) >/dev/null; then $(2); \
	elif [[ "$(STRICT)" == 1 ]]; then echo "missing required tool: $(1)" >&2; exit 1; \
	else echo "skipping $(1) (not installed)"; fi
endef

lint-shell:
	@$(call optional_tool,shellcheck,shellcheck -x $(SHELL_FILES))
	@$(call optional_tool,shfmt,shfmt -d -i 4 -ci $(SHELL_FILES))

lint-lists:
	tests/static/check-package-lists.sh

lint-configs:
	tests/static/check-configs.sh

lint-meta:
	scripts/gen-meta.sh --check

lint-docs:
	tests/static/check-readme-commands.sh
	@$(call optional_tool,markdownlint-cli2,markdownlint-cli2 README.md 'docs/**/*.md')
	@$(call optional_tool,lychee,lychee --no-progress README.md docs)

# ---------------------------------------------------------------- layer 2
unit:
	$(BATS) --recursive tests/unit

# ---------------------------------------------------------------- layer 3
repo:
	$(SUDO) scripts/build-repo.sh

packages: repo packages-tests

packages-tests:
	tests/packages/resolve-matrix.sh
	$(if $(filter 0,$(shell id -u)),,$(SUDO)) tests/packages/smoke.sh

# ---------------------------------------------------------------- layer 4/5
iso:
	$(SUDO) scripts/build-iso.sh

test-iso:
	$(PYTEST) tests/integration -m "not a11y" --iso "$(ISO)" $(PYTEST_ARGS) \
		$(if $(CASES),--cases "$(CASES)") $(if $(FIRMWARE),--firmware "$(FIRMWARE)")

test-a11y:
	$(PYTEST) tests/a11y -m a11y --iso "$(ISO)" $(PYTEST_ARGS)

# ---------------------------------------------------------------- shortcuts
test: lint unit

ci: lint unit

meta:
	scripts/gen-meta.sh

lock:
	scripts/aur-lock.sh

clean:
	rm -rf build out
