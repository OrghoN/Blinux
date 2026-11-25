# Shared setup for the bats unit tests.

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURES="$REPO/tests/fixtures"
TOOLS="$REPO/tools/bin"
export LOG_FILE=/dev/null

# Stub commands that would touch the real system. Each stub logs its
# arguments to $STUB_LOG so tests can assert on them.
setup_stubs() {
    STUBS="$BATS_TEST_TMPDIR/stubs"
    STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    export STUB_LOG
    mkdir -p "$STUBS"
    local cmd
    for cmd in "$@"; do
        printf '#!/bin/sh\necho "%s $*" >>"$STUB_LOG"\n' "$cmd" >"$STUBS/$cmd"
        chmod +x "$STUBS/$cmd"
    done
    PATH="$STUBS:$PATH"
}

# Load the tool libraries into the test's shell.
load_libs() {
    # shellcheck source=/dev/null
    source "$REPO/tools/lib/common.sh"
    # shellcheck source=/dev/null
    source "$REPO/tools/lib/detect.sh"
    # shellcheck source=/dev/null
    source "$REPO/tools/lib/drivers.sh"
    # shellcheck source=/dev/null
    source "$REPO/tools/lib/packages.sh"
}

# Run the installer in dry-run mode on an install fixture.
install_dry_run() {
    run env DRY_RUN=1 BLINUX_ONLINE="${ONLINE:-1}" BLINUX_OFFLINE="${OFFLINE:-0}" \
        OFFLINE_REPO="${OFFLINE_REPO:-/nonexistent}" "$TOOLS/blinux-install" --dry-run \
        --config "$1"
}
